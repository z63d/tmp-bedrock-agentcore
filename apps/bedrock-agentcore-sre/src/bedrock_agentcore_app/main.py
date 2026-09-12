from __future__ import annotations

import asyncio
import logging
import os
import threading
import uuid
from datetime import datetime, timezone
from typing import Any, AsyncIterator

import boto3
import structlog
from bedrock_agentcore import BedrockAgentCoreApp
from mcp_proxy_for_aws.client import aws_iam_streamablehttp_client
from strands import Agent, AgentSkills
from strands.models import BedrockModel
from strands.models.bedrock import CacheConfig
from strands.tools.mcp import MCPClient

from bedrock_agentcore_app.prompts import INVESTIGATION_SYSTEM_PROMPT, ORCHESTRATOR_SYSTEM_PROMPT


class MemoryClient:
    def __init__(self, region: str, memory_id: str) -> None:
        self.region = region
        self.memory_id = memory_id
        self._client: Any = None

    def _get_client(self) -> Any:
        if self._client is None:
            self._client = boto3.client("bedrock-agentcore", region_name=self.region)
        return self._client

    def _list_events(self, session_id: str, max_results: int = 20) -> list[dict[str, str]]:
        client = self._get_client()
        response = client.list_events(
            memoryId=self.memory_id,
            sessionId=session_id,
            actorId="user",
            maxResults=max_results,
        )
        turns: list[dict[str, str]] = []
        for event in response.get("events", []):
            for item in event.get("payload", []):
                conv = item.get("conversational", {})
                role = conv.get("role", "")
                text = conv.get("content", {}).get("text", "")
                if role and text:
                    turns.append({"role": role, "text": text})
        return turns

    def _create_event(self, session_id: str, user_message: str, assistant_message: str) -> None:
        client = self._get_client()
        client.create_event(
            memoryId=self.memory_id,
            actorId="user",
            sessionId=session_id,
            eventTimestamp=datetime.now(timezone.utc),
            payload=[
                {"conversational": {"role": "USER", "content": {"text": user_message}}},
                {
                    "conversational": {
                        "role": "ASSISTANT",
                        "content": {"text": assistant_message},
                    }
                },
            ],
        )

    async def get_conversation_history(self, session_id: str) -> list[dict[str, str]]:
        try:
            return await asyncio.to_thread(self._list_events, session_id)
        except Exception as e:
            logger.warning("Failed to get conversation history", error=str(e))
            return []

    async def store_conversation(
        self, session_id: str, user_message: str, assistant_message: str
    ) -> None:
        try:
            await asyncio.to_thread(self._create_event, session_id, user_message, assistant_message)
        except Exception as e:
            logger.warning("Failed to store conversation", error=str(e))


logging.basicConfig(format="%(message)s", level=os.environ.get("LOG_LEVEL", "WARNING").upper())

structlog.configure(
    processors=[
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.stdlib.PositionalArgumentsFormatter(),
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.UnicodeDecoder(),
        structlog.processors.JSONRenderer(),
    ],
    wrapper_class=structlog.stdlib.BoundLogger,
    context_class=dict,
    logger_factory=structlog.stdlib.LoggerFactory(),
    cache_logger_on_first_use=True,
)

logger = structlog.get_logger()

region = os.environ["AWS_REGION"]
model_id = os.environ["BEDROCK_MODEL_ID"]
memory_id = os.environ.get("MEMORY_ID")
gateway_id = os.environ.get("GATEWAY_ID")
eks_cluster_name = os.environ.get("EKS_CLUSTER_NAME")
mysql_secret_arn = os.environ.get("MYSQL_SECRET_ARN")

memory_client: MemoryClient | None = None
if memory_id:
    memory_client = MemoryClient(region=region, memory_id=memory_id)

mcp_client: MCPClient | None = None
if gateway_id:
    gateway_url = f"https://{gateway_id}.gateway.bedrock-agentcore.{region}.amazonaws.com/mcp"
    try:
        mcp_client = MCPClient(
            lambda: aws_iam_streamablehttp_client(
                endpoint=gateway_url,
                aws_region=region,
                aws_service="bedrock-agentcore",
            )
        )
    except Exception as e:
        logger.error("Failed to initialize MCP Gateway client", error=str(e), gateway_id=gateway_id)
        mcp_client = None

app = BedrockAgentCoreApp()

_investigation_agent: Agent | None = None
_investigation_agent_lock = threading.Lock()


def _get_investigation_agent() -> Agent:
    global _investigation_agent

    if _investigation_agent is not None:
        return _investigation_agent

    with _investigation_agent_lock:
        if _investigation_agent is not None:
            return _investigation_agent

        investigation_tools: list[Any] = []
        if mcp_client:
            investigation_tools.append(mcp_client)

        if eks_cluster_name:
            from bedrock_agentcore_app.tools.k8s import k8s_tools

            investigation_tools.extend(k8s_tools)

        if mysql_secret_arn:
            from bedrock_agentcore_app.tools.mysql import mysql_tools

            investigation_tools.extend(mysql_tools)

        _investigation_agent = Agent(
            name="investigation_agent",
            model=BedrockModel(
                region_name=region,
                model_id=model_id,
                max_tokens=4096,
                cache_config=CacheConfig(strategy="auto"),
            ),
            tools=investigation_tools,
            plugins=[AgentSkills(skills=["./skills/newrelic", "./skills/mysql"])],
            system_prompt=INVESTIGATION_SYSTEM_PROMPT,
            callback_handler=None,
        )

        return _investigation_agent


def _create_orchestrator() -> Agent:
    investigation_agent = _get_investigation_agent()

    return Agent(
        model=BedrockModel(
            region_name=region,
            model_id=model_id,
            max_tokens=4096,
            cache_config=CacheConfig(strategy="auto"),
        ),
        tools=[
            investigation_agent.as_tool(
                name="investigation_agent",
                description="SRE investigation specialist with access to various tools via MCP Gateway (monitoring, error tracking, cloud infrastructure, databases, document management, etc), Kubernetes tools for EKS, and MySQL read-only query tools. Delegates any investigation, monitoring, or operational task.",
            ),
        ],
        plugins=[AgentSkills(skills=["./skills/report"])],
        system_prompt=ORCHESTRATOR_SYSTEM_PROMPT,
    )


@app.entrypoint
async def invoke(payload: dict[str, Any]) -> AsyncIterator[dict[str, Any]]:
    prompt = payload.get("prompt")
    session_id = payload.get("sessionId") or str(uuid.uuid4())

    if not isinstance(prompt, str) or not prompt.strip():
        logger.warning(
            "Invalid or empty prompt", session_id=session_id, prompt_type=type(prompt).__name__
        )
        yield {"error": "prompt must be a non-empty string", "sessionId": session_id}
        return

    context_parts: list[str] = []
    if memory_client:
        stm = await memory_client.get_conversation_history(session_id)
        if stm:
            history = "\n".join(f"{t['role']}: {t['text']}" for t in stm)
            context_parts.append(f"[Conversation history]\n{history}")

    context_prompt = (
        "\n\n".join([*context_parts, f"[Current question]\n{prompt}"]) if context_parts else prompt
    )

    agent = _create_orchestrator()

    try:
        # agent() is sync (blocks until all tool calls finish); 120s cap prevents runaway loops
        result = await asyncio.wait_for(asyncio.to_thread(agent, context_prompt), timeout=120)
        response_text = str(result)

        if memory_client:
            await memory_client.store_conversation(session_id, prompt, response_text)

        yield {"text": response_text, "sessionId": session_id}

    except TimeoutError:
        logger.error("Agent invoke timed out", session_id=session_id)
        yield {"error": "Request timed out.", "sessionId": session_id}

    except Exception as error:
        logger.error(
            "Agent invoke error",
            session_id=session_id,
            error=str(error),
            error_type=type(error).__name__,
        )
        yield {"error": "An internal error occurred.", "sessionId": session_id}


def main() -> None:
    app.run()


if __name__ == "__main__":
    main()
