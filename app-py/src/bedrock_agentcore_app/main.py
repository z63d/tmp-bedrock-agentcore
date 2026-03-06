"""
Bedrock AgentCore Application Entry Point.

Phase 1: LLM-only agent with streaming response.
- No tools
- No memory
- No MCP Gateway
"""

from __future__ import annotations

import os
import uuid
from typing import Any, AsyncIterator

import structlog
from bedrock_agentcore import BedrockAgentCoreApp
from strands import Agent
from strands.models import BedrockModel

# Configure structured logging (JSON format)
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

# Configuration from environment
region = os.environ.get("AWS_REGION", "ap-northeast-1")
model_id = os.environ.get("BEDROCK_MODEL_ID", "amazon.nova-lite-v1:0")

# Create BedrockAgentCoreApp instance
app = BedrockAgentCoreApp()

# Create agent (singleton, lazy initialization)
_agent: Agent | None = None


def get_agent() -> Agent:
    """
    Get or create the Strands Agent (singleton pattern).

    Returns:
        Configured Agent instance
    """
    global _agent

    if _agent is not None:
        return _agent

    logger.info(
        "Creating agent",
        region=region,
        model_id=model_id,
    )

    _agent = Agent(
        model=BedrockModel(
            region_name=region,
            model_id=model_id,
            max_tokens=4096,
        ),
        system_prompt="You are a helpful assistant.",
    )

    return _agent


@app.entrypoint
async def invoke(payload: dict[str, Any]) -> AsyncIterator[dict[str, Any]]:
    """
    Handle agent invocation requests with streaming response.

    Args:
        payload: Request payload containing prompt and optional sessionId

    Yields:
        Response events with text and sessionId
    """
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

    agent = get_agent()

    try:
        # Invoke agent synchronously
        result = agent(prompt)
        response_text = str(result)

        logger.info(
            "Response generated",
            session_id=session_id,
            response_length=len(response_text),
        )

        # Yield final response
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
    )
    app.run()


if __name__ == "__main__":
    main()
