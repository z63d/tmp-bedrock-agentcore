"""Gateway MCP Client for AgentCore Gateway integration."""

from __future__ import annotations

import structlog
from mcp_proxy_for_aws.client import aws_iam_streamablehttp_client
from strands.tools.mcp import MCPClient

logger = structlog.get_logger()


def create_gateway_mcp_client(
    region: str,
    gateway_id: str,
    application_name: str = "bedrock-agentcore-app",
    application_version: str = "1.0.0",
) -> MCPClient:
    """
    Create an MCP client for AgentCore Gateway with SigV4 authentication.

    The client uses mcp-proxy-for-aws for automatic AWS SigV4 request signing.

    Args:
        region: AWS region (e.g., "ap-northeast-1")
        gateway_id: Gateway ID extracted from Gateway ARN
        application_name: Application name for MCP client identification
        application_version: Application version

    Returns:
        Configured MCPClient instance
    """
    gateway_url = f"https://{gateway_id}.gateway.bedrock-agentcore.{region}.amazonaws.com/mcp"

    logger.info(
        "Creating Gateway MCP client",
        gateway_url=gateway_url,
        application_name=application_name,
        application_version=application_version,
    )

    def mcp_client_factory():
        return aws_iam_streamablehttp_client(
            endpoint=gateway_url,
            aws_region=region,
            aws_service="bedrock-agentcore",
        )

    return MCPClient(
        mcp_client_factory,
        name=application_name,
        version=application_version,
    )
