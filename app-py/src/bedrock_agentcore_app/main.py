"""
Bedrock AgentCore Application Entry Point.

Phase 3: Agent with Calculator tool and Memory integration.
- Calculator tool for mathematical operations
- Memory for conversation history storage and retrieval
- No MCP Gateway
"""

from __future__ import annotations

import os
import uuid
from datetime import datetime, timezone
from typing import Any, AsyncIterator

import boto3
import structlog
from bedrock_agentcore import BedrockAgentCoreApp
from strands import Agent, tool
from strands.models import BedrockModel


# =============================================================================
# Tools
# =============================================================================


@tool
def calculator(operation: str, a: float, b: float) -> str:
    """
    Perform mathematical calculations.

    Args:
        operation: The mathematical operation to perform (add, subtract, multiply, divide)
        a: First number
        b: Second number

    Returns:
        Result of the calculation as a formatted string
    """
    match operation:
        case "add":
            return f"Result: {a} + {b} = {a + b}"
        case "subtract":
            return f"Result: {a} - {b} = {a - b}"
        case "multiply":
            return f"Result: {a} * {b} = {a * b}"
        case "divide":
            if b == 0:
                return "Error: Division by zero"
            return f"Result: {a} / {b} = {a / b}"
        case _:
            return f"Unknown operation: {operation}"


# =============================================================================
# Memory Client
# =============================================================================


class MemoryClient:
    """Simple client for AgentCore Memory API."""

    def __init__(self, region: str, memory_id: str) -> None:
        self.region = region
        self.memory_id = memory_id
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
                namespace="/",
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
                    {"conversational": {"role": "ASSISTANT", "content": {"text": assistant_message}}},
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
model_id = os.environ.get("BEDROCK_MODEL_ID", "amazon.nova-lite-v1:0")
memory_id = os.environ.get("MEMORY_ID")

# Initialize Memory Client (optional)
memory_client: MemoryClient | None = None
if memory_id:
    memory_client = MemoryClient(region=region, memory_id=memory_id)
    logger.info("Memory enabled", memory_id=memory_id)
else:
    logger.info("Memory disabled (MEMORY_ID not set)")

# Create BedrockAgentCoreApp instance
app = BedrockAgentCoreApp()

# Create agent (singleton, lazy initialization)
_agent: Agent | None = None


def get_agent() -> Agent:
    """Get or create the Strands Agent (singleton pattern)."""
    global _agent

    if _agent is not None:
        return _agent

    logger.info("Creating agent", region=region, model_id=model_id)

    system_prompt = """You are a helpful assistant.

When asked to perform calculations, use the calculator tool.
The calculator supports: add, subtract, multiply, divide operations."""

    _agent = Agent(
        model=BedrockModel(
            region_name=region,
            model_id=model_id,
            max_tokens=4096,
        ),
        tools=[calculator],
        system_prompt=system_prompt,
    )

    return _agent


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
                context_prompt = f"[Previous context]\n{memory_context}\n\n[Current question]\n{prompt}"
                logger.info("Found relevant memories", count=len(memory_texts))

    agent = get_agent()

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
    )
    app.run()


if __name__ == "__main__":
    main()
