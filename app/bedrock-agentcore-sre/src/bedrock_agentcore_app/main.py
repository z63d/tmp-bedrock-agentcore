"""
Bedrock AgentCore Application Entry Point.

Multi-agent architecture (Agents-as-Tools pattern):
- Orchestrator agent: routes user requests to specialized sub-agents
- Investigation agent: SRE tool specialist with MCP Gateway access
"""

from __future__ import annotations

import os
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

# =============================================================================
# Memory Client
# =============================================================================


class MemoryClient:
    """Simple client for AgentCore Memory API."""

    def __init__(self, region: str, memory_id: str, namespace: str) -> None:
        self.region = region
        self.memory_id = memory_id
        self.namespace = namespace
        self._client: Any = None

    def _get_client(self) -> Any:
        if self._client is None:
            self._client = boto3.client("bedrock-agentcore", region_name=self.region)
        return self._client

    async def search_memories(self, query: str, top_k: int = 3) -> list[dict[str, Any]]:
        """Search memories using vector similarity."""
        client = self._get_client()
        try:
            response = client.retrieve_memory_records(
                memoryId=self.memory_id,
                namespace=self.namespace,
                searchCriteria={"searchQuery": query, "topK": top_k},
            )
            return response.get("memoryRecordSummaries", [])
        except Exception as e:
            logger.warning("Failed to search memories", error=str(e))
            return []

    async def store_conversation(
        self, session_id: str, user_message: str, assistant_message: str
    ) -> None:
        """Store a conversation turn in memory."""
        client = self._get_client()
        try:
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
            logger.info("Stored conversation in memory", session_id=session_id)
        except Exception as e:
            logger.warning("Failed to store conversation", error=str(e))


# =============================================================================
# Logging Configuration
# =============================================================================

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


# =============================================================================
# Configuration
# =============================================================================

region = os.environ.get("AWS_REGION", "ap-northeast-1")
model_id = os.environ["BEDROCK_MODEL_ID"]
memory_id = os.environ.get("MEMORY_ID")
memory_namespace = os.environ.get("MEMORY_NAMESPACE", "/")
gateway_id = os.environ.get("GATEWAY_ID")
eks_cluster_name = os.environ.get("EKS_CLUSTER_NAME")
mysql_secret_arn = os.environ.get("MYSQL_SECRET_ARN")

# Initialize Memory Client (optional)
memory_client: MemoryClient | None = None
if memory_id:
    memory_client = MemoryClient(region=region, memory_id=memory_id, namespace=memory_namespace)
    logger.info("Memory enabled", memory_id=memory_id)
else:
    logger.info("Memory disabled (MEMORY_ID not set)")

# Initialize MCP Gateway Client (optional)
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
        logger.info("MCP Gateway enabled", gateway_id=gateway_id, gateway_url=gateway_url)
    except Exception as e:
        logger.error("Failed to initialize MCP Gateway client", error=str(e), gateway_id=gateway_id)
        mcp_client = None
else:
    logger.info("MCP Gateway disabled (GATEWAY_ID not set)")

# Create BedrockAgentCoreApp instance
app = BedrockAgentCoreApp()

# Create agents (singleton, lazy initialization)
_orchestrator: Agent | None = None


def get_orchestrator() -> Agent:
    """Get or create the orchestrator Agent (singleton pattern)."""
    global _orchestrator

    if _orchestrator is not None:
        return _orchestrator

    logger.info(
        "Creating multi-agent system",
        region=region,
        model_id=model_id,
        mcp_enabled=mcp_client is not None,
    )

    investigation_tools: list[Any] = []
    if mcp_client:
        investigation_tools.append(mcp_client)

    if eks_cluster_name:
        from bedrock_agentcore_app.tools.k8s import k8s_tools

        investigation_tools.extend(k8s_tools)
        logger.info("K8s tools enabled", cluster=eks_cluster_name)

    if mysql_secret_arn:
        from bedrock_agentcore_app.tools.mysql import mysql_tools

        investigation_tools.extend(mysql_tools)
        logger.info("MySQL tools enabled")

    skills_plugin = AgentSkills(skills=["./skills/newrelic", "./skills/mysql"])

    investigation_agent = Agent(
        name="investigation_agent",
        model=BedrockModel(
            region_name=region,
            model_id=model_id,
            max_tokens=4096,
            cache_config=CacheConfig(strategy="auto"),
        ),
        tools=investigation_tools,
        plugins=[skills_plugin],
        system_prompt=INVESTIGATION_SYSTEM_PROMPT,
        callback_handler=None,
    )

    orchestrator_skills = AgentSkills(skills=["./skills/report"])

    _orchestrator = Agent(
        model=BedrockModel(
            region_name=region,
            model_id=model_id,
            max_tokens=4096,
            cache_config=CacheConfig(strategy="auto"),
        ),
        tools=[
            investigation_agent.as_tool(
                name="investigation_agent",
                description="SRE investigation specialist. Delegates infrastructure monitoring, log analysis, metric queries, error tracking, Kubernetes cluster inspection, MySQL database queries, and incident investigation tasks. Has access to New Relic, AWS CloudWatch, Rollbar tools via MCP Gateway, Kubernetes tools for EKS, and MySQL read-only query tools.",
            ),
        ],
        plugins=[orchestrator_skills],
        system_prompt=ORCHESTRATOR_SYSTEM_PROMPT,
    )

    return _orchestrator


# =============================================================================
# Entrypoint
# =============================================================================


@app.entrypoint
async def invoke(payload: dict[str, Any]) -> AsyncIterator[dict[str, Any]]:
    """Handle agent invocation requests."""
    prompt = payload.get("prompt", "")
    session_id = payload.get("sessionId") or str(uuid.uuid4())

    logger.info(
        "Received request",
        session_id=session_id,
        prompt_length=len(prompt),
        prompt_preview=prompt[:100] if prompt else "",
    )

    if not prompt:
        logger.warning("Empty prompt received", session_id=session_id)
        yield {"error": "prompt is required", "sessionId": session_id}
        return

    # Build context with memory
    context_prompt = prompt
    if memory_client:
        memories = await memory_client.search_memories(prompt, top_k=3)
        if memories:
            memory_texts = [
                m.get("content", {}).get("text", "")
                for m in memories
                if m.get("content", {}).get("text")
            ]
            if memory_texts:
                memory_context = "\n".join(memory_texts)
                context_prompt = (
                    f"[Previous context]\n{memory_context}\n\n[Current question]\n{prompt}"
                )
                logger.info("Found relevant memories", count=len(memory_texts))

    agent = get_orchestrator()

    try:
        result = agent(context_prompt)
        response_text = str(result)

        logger.info(
            "Response generated",
            session_id=session_id,
            response_length=len(response_text),
        )

        # Store conversation in memory
        if memory_client:
            await memory_client.store_conversation(session_id, prompt, response_text)

        yield {"text": response_text, "sessionId": session_id}

    except Exception as error:
        logger.error(
            "Agent invoke error",
            session_id=session_id,
            error=str(error),
            error_type=type(error).__name__,
        )
        yield {"error": str(error), "sessionId": session_id}


def main() -> None:
    """Entry point for the application."""
    logger.info(
        "Starting AgentCore Runtime server",
        port=8080,
        region=region,
        model_id=model_id,
        memory_enabled=memory_client is not None,
        mcp_enabled=mcp_client is not None,
    )
    app.run()


if __name__ == "__main__":
    main()
