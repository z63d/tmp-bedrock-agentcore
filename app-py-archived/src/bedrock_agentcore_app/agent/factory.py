"""Agent factory for creating Strands Agents with tools."""

from __future__ import annotations

import os
from typing import TYPE_CHECKING

import structlog
from strands import Agent, tool
from strands.models import BedrockModel

if TYPE_CHECKING:
    from strands.tools.mcp import MCPClient

logger = structlog.get_logger()


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


def build_system_prompt(has_mcp_tools: bool) -> str:
    """
    Build system prompt based on available tools.

    Args:
        has_mcp_tools: Whether MCP tools are available

    Returns:
        System prompt string
    """
    base_prompt = "You are a helpful assistant."

    tool_instructions = [
        "When asked to perform calculations, use the calculator tool.",
    ]

    if has_mcp_tools:
        tool_instructions.extend([
            "For Rollbar error tracking queries (items, deployments, versions, errors, bugs, incidents), use the Rollbar tools.",
            "For CloudWatch monitoring queries (alarms, metrics, logs), use the CloudWatch tools.",
        ])

    return f"{base_prompt}\n\n" + "\n".join(tool_instructions)


async def create_agent(mcp_client: MCPClient | None = None, system_prompt: str | None = None) -> Agent:
    """
    Create an agent with optional MCP tools.

    Args:
        mcp_client: Optional MCP client for Gateway integration
        system_prompt: Optional system prompt override

    Returns:
        Configured Agent instance
    """
    region = os.environ.get("AWS_REGION", "ap-northeast-1")
    model_id = os.environ.get("BEDROCK_MODEL_ID", "amazon.nova-lite-v1:0")

    tools: list = [calculator]

    if mcp_client:
        tools.append(mcp_client)

    prompt = system_prompt or build_system_prompt(mcp_client is not None)

    logger.info(
        "Creating agent",
        region=region,
        model_id=model_id,
        has_mcp_tools=mcp_client is not None,
    )

    return Agent(
        model=BedrockModel(
            region_name=region,
            model_id=model_id,
            max_tokens=4096,
        ),
        tools=tools,
        system_prompt=prompt,
    )


async def create_default_agent() -> Agent:
    """
    Create a default agent without MCP tools (for backward compatibility).

    Returns:
        Configured Agent instance without MCP tools
    """
    return await create_agent()
