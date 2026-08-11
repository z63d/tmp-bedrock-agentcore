"""
Bedrock AgentCore Application Entry Point.

This module initializes and runs the BedrockAgentCoreApp runtime server
with optional MCP Gateway and Memory integration.
"""

from __future__ import annotations

import os
from typing import TYPE_CHECKING, Any, AsyncIterator

import structlog
from bedrock_agentcore import BedrockAgentCoreApp
from dotenv import load_dotenv
from strands import Agent
from strands.models import BedrockModel
from strands.tools.mcp import MCPClient

from .agent.factory import calculator, build_system_prompt
from .mcp import create_gateway_mcp_client
from .memory import AgentCoreMemoryClient
from .memory.client import ConversationTurn, MessageRole

if TYPE_CHECKING:
    pass

# Load environment variables
load_dotenv()

# Configure structured logging
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
memory_id = os.environ.get("MEMORY_ID")
gateway_arn = os.environ.get("GATEWAY_ARN")
model_id = os.environ.get("BEDROCK_MODEL_ID", "amazon.nova-lite-v1:0")

# Initialize Memory Client (optional)
memory_client: AgentCoreMemoryClient | None = None
if memory_id:
    memory_client = AgentCoreMemoryClient(region=region, memory_id=memory_id)
    logger.info("Memory enabled", memory_id=memory_id)
else:
    logger.info("Memory disabled (MEMORY_ID not set)")

# Extract gatewayId from ARN: arn:aws:bedrock-agentcore:{region}:{account}:gateway/{gatewayId}
gateway_id = gateway_arn.split("/")[-1] if gateway_arn else None
if gateway_id:
    logger.info("Gateway MCP enabled", gateway_arn=gateway_arn)
else:
    logger.info("Gateway MCP disabled (GATEWAY_ARN not set)")

# MCP Client (initialized once, used as context manager)
mcp_client: MCPClient | None = None
if gateway_id:
    mcp_client = create_gateway_mcp_client(region=region, gateway_id=gateway_id)

# Cache for agent (lazy loaded on first request)
agent_cache: Agent | None = None

# Create BedrockAgentCoreApp instance
app = BedrockAgentCoreApp()


def create_agent_with_tools(mcp_tools: list | None = None) -> Agent:
    """
    Create an agent with optional MCP tools.

    Args:
        mcp_tools: List of MCP tools from MCPClient.list_tools_sync()

    Returns:
        Configured Agent instance
    """
    tools: list = [calculator]
    has_mcp_tools = False

    if mcp_tools:
        tools.extend(mcp_tools)
        has_mcp_tools = True
        logger.info("MCP tools loaded", tool_count=len(mcp_tools))

    system_prompt = build_system_prompt(has_mcp_tools)

    logger.info(
        "Creating agent",
        region=region,
        model_id=model_id,
        has_mcp_tools=has_mcp_tools,
        tool_count=len(tools),
    )

    return Agent(
        model=BedrockModel(
            region_name=region,
            model_id=model_id,
            max_tokens=4096,
        ),
        tools=tools,
        system_prompt=system_prompt,
    )


def get_or_create_agent() -> Agent:
    """
    Get or create agent with MCP tools (lazy initialization).

    Returns:
        Configured Agent instance
    """
    global agent_cache

    if agent_cache is not None:
        return agent_cache

    if not mcp_client:
        logger.info("No MCP client, using default agent")
        agent_cache = create_agent_with_tools()
        return agent_cache

    try:
        # Use context manager to establish MCP connection and get tools
        with mcp_client:
            mcp_tools = mcp_client.list_tools_sync()
            logger.info(
                "MCP tools discovered",
                tools=[t.name if hasattr(t, 'name') else str(t) for t in mcp_tools],
            )
            agent_cache = create_agent_with_tools(mcp_tools)
        return agent_cache
    except Exception as error:
        logger.warning("Failed to create MCP agent, falling back to default", error=str(error))
        agent_cache = create_agent_with_tools()
        return agent_cache


@app.entrypoint
async def invoke(payload: dict[str, Any]) -> AsyncIterator[dict[str, Any]]:
    """
    Handle agent invocation requests.

    Args:
        payload: Request payload containing prompt and sessionId

    Yields:
        Response events (message or error)
    """
    prompt = payload.get("prompt", "")
    session_id = payload.get("sessionId", "default")
    actor_id = "user"

    logger.info("Received prompt", session_id=session_id, prompt=prompt[:100])

    # Get agent (lazy loads MCP tools on first request)
    agent = get_or_create_agent()

    # Prepare context prompt
    context_prompt = prompt

    # Retrieve relevant memories if available
    if memory_client:
        try:
            memories = await memory_client.search_memories(prompt, "/", 3)
            if memories:
                memory_texts = [
                    m.content.get("text", "")
                    for m in memories
                    if m.content and m.content.get("text")
                ]
                if memory_texts:
                    memory_context = "\n".join(memory_texts)
                    context_prompt = (
                        f"[Previous context]\n{memory_context}\n\n"
                        f"[Current question]\n{prompt}"
                    )
                    logger.info("Found relevant memories", count=len(memories))
        except Exception as error:
            logger.warning("Failed to retrieve memories", error=str(error))

    # Invoke agent
    try:
        result = agent(context_prompt)
        response = str(result)
    except Exception as invoke_error:
        logger.error(
            "Agent invoke error",
            error=str(invoke_error),
            error_type=type(invoke_error).__name__,
        )
        yield {"error": str(invoke_error), "sessionId": session_id}
        return

    # Store conversation in memory
    if memory_client:
        try:
            await memory_client.create_event(
                actor_id=actor_id,
                session_id=session_id,
                turns=[
                    ConversationTurn(role=MessageRole.USER, content=prompt),
                    ConversationTurn(role=MessageRole.ASSISTANT, content=response),
                ],
            )
            logger.info("Conversation stored in memory")
        except Exception as error:
            logger.warning("Failed to store conversation", error=str(error))

    # Yield response
    yield {"text": response, "sessionId": session_id}


def main() -> None:
    """Entry point for the application."""
    logger.info("Starting AgentCore Runtime server on port 8080...")
    app.run()


if __name__ == "__main__":
    main()
