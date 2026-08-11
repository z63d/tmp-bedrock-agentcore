"""CloudWatch MCP Gateway Client for JSON-RPC tool invocation."""

from __future__ import annotations

import json
import re
import time
from typing import Any

import structlog
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
from botocore.session import get_session
from pydantic import BaseModel

logger = structlog.get_logger()


class ToolExecutionResult(BaseModel):
    """Result of a tool execution."""

    tool_name: str
    input: dict[str, Any]
    output: Any


class CloudWatchResponse(BaseModel):
    """Response from CloudWatch tool invocation."""

    text: str
    tool_results: list[ToolExecutionResult] = []


class MCPToolInfo(BaseModel):
    """Information about an MCP tool."""

    name: str
    description: str | None = None
    input_schema: dict[str, Any] | None = None


class CloudWatchResponsesClient:
    """
    CloudWatch client using AgentCore Gateway with MCP protocol.

    Gateway URL format: https://{gateway-id}.gateway.bedrock-agentcore.{region}.amazonaws.com/mcp
    """

    # Keyword to tool mapping (bilingual: English and Japanese)
    TOOL_KEYWORDS: dict[str, list[str]] = {
        "get_active_alarms": ["alarm", "alert", "アラーム", "発報"],
        "get_alarm_history": ["alarm history", "アラーム履歴"],
        "get_metric_data": ["metric", "メトリクス", "cpu", "memory", "utilization"],
        "analyze_metric": ["analyze", "trend", "分析", "傾向"],
        "describe_log_groups": ["log group", "ロググループ", "list log"],
        "analyze_log_group": ["log", "error", "ログ", "エラー"],
        "execute_log_insights_query": ["insights", "query", "クエリ"],
    }

    def __init__(self, region: str, gateway_id: str) -> None:
        """
        Initialize the CloudWatch client.

        Args:
            region: AWS region
            gateway_id: Gateway ID from ARN
        """
        self.region = region
        self.gateway_endpoint = (
            f"https://{gateway_id}.gateway.bedrock-agentcore.{region}.amazonaws.com/mcp"
        )
        self._session = get_session()
        self._credentials = self._session.get_credentials()

    async def list_tools(self) -> list[MCPToolInfo]:
        """List available tools from the gateway."""
        response = await self._send_mcp_request("tools/list", {})
        tools_data = response.get("tools", []) if isinstance(response, dict) else []
        return [
            MCPToolInfo(
                name=t.get("name", ""),
                description=t.get("description"),
                input_schema=t.get("inputSchema"),
            )
            for t in tools_data
        ]

    async def call_tool(self, tool_name: str, args: dict[str, Any]) -> Any:
        """Call a specific tool via the gateway."""
        return await self._send_mcp_request(
            "tools/call",
            {"name": tool_name, "arguments": args},
        )

    async def invoke(self, prompt: str) -> CloudWatchResponse:
        """
        Invoke the CloudWatch agent with a natural language prompt.

        Args:
            prompt: Natural language prompt

        Returns:
            CloudWatchResponse with formatted result
        """
        logger.info("CloudWatch MCP Gateway invoke", prompt=prompt[:100])

        try:
            tools = await self.list_tools()
            logger.info("Available tools", tools=[t.name for t in tools])

            tool_to_call = self._select_tool_for_prompt(prompt, tools)

            if not tool_to_call:
                return CloudWatchResponse(
                    text=f"No matching CloudWatch tool found. Available tools: {', '.join(t.name for t in tools)}",
                    tool_results=[],
                )

            tool_args = self._build_tool_arguments(tool_to_call, prompt)
            logger.info("Calling tool", tool=tool_to_call.name, args=tool_args)

            tool_result = await self.call_tool(tool_to_call.name, tool_args)
            logger.info("Tool result received", tool=tool_to_call.name)

            return CloudWatchResponse(
                text=self._format_tool_result(tool_to_call.name, tool_result),
                tool_results=[
                    ToolExecutionResult(
                        tool_name=tool_to_call.name,
                        input=tool_args,
                        output=tool_result,
                    )
                ],
            )
        except Exception as e:
            logger.error("CloudWatch MCP error", error=str(e))
            raise

    async def _send_mcp_request(
        self,
        method: str,
        params: dict[str, Any],
    ) -> Any:
        """Send a JSON-RPC request to the MCP Gateway with SigV4 signing."""
        import httpx

        request_body = {
            "jsonrpc": "2.0",
            "id": f"request-{int(time.time() * 1000)}",
            "method": method,
            "params": params,
        }

        body_bytes = json.dumps(request_body).encode("utf-8")

        aws_request = AWSRequest(
            method="POST",
            url=self.gateway_endpoint,
            headers={"Content-Type": "application/json"},
            data=body_bytes,
        )

        SigV4Auth(self._credentials, "bedrock-agentcore", self.region).add_auth(
            aws_request
        )

        logger.debug("MCP Request", endpoint=self.gateway_endpoint, method=method)

        async with httpx.AsyncClient() as client:
            response = await client.post(
                self.gateway_endpoint,
                headers=dict(aws_request.headers),
                content=body_bytes,
            )

        logger.debug("MCP Response", status=response.status_code)

        if not response.is_success:
            raise RuntimeError(
                f"MCP Gateway error: {response.status_code} - {response.text}"
            )

        result = response.json()

        if "error" in result:
            error_msg = result["error"].get("message", json.dumps(result["error"]))
            raise RuntimeError(f"MCP error: {error_msg}")

        return result.get("result")

    def _get_base_tool_name(self, full_name: str) -> str:
        """Extract base tool name from Gateway's prefixed format (target___tool)."""
        parts = full_name.split("___")
        return parts[-1] if len(parts) > 1 else full_name

    def _select_tool_for_prompt(
        self,
        prompt: str,
        tools: list[MCPToolInfo],
    ) -> MCPToolInfo | None:
        """Select the appropriate tool based on the prompt using keyword matching."""
        lower_prompt = prompt.lower()

        for tool in tools:
            base_name = self._get_base_tool_name(tool.name)
            keywords = self.TOOL_KEYWORDS.get(base_name) or self.TOOL_KEYWORDS.get(
                tool.name
            )
            if keywords and any(kw in lower_prompt for kw in keywords):
                return tool

        # Default to get_active_alarms
        default_tool = next(
            (
                t
                for t in tools
                if self._get_base_tool_name(t.name) == "get_active_alarms"
            ),
            None,
        )
        return default_tool or (tools[0] if tools else None)

    def _build_tool_arguments(
        self,
        tool: MCPToolInfo,
        prompt: str,
    ) -> dict[str, Any]:
        """Build tool arguments based on the tool type."""
        base_name = self._get_base_tool_name(tool.name)

        match base_name:
            case "get_active_alarms":
                return {"state_value": "ALARM"}
            case "get_metric_data":
                return {
                    "namespace": "AWS/EC2",
                    "metric_name": "CPUUtilization",
                    "period": 300,
                    "stat": "Average",
                }
            case "describe_log_groups":
                return {"limit": 10}
            case "analyze_log_group":
                return {"hours": 1}
            case _:
                return {}

    def _format_tool_result(self, tool_name: str, result: Any) -> str:
        """Format tool result into human-readable text."""
        if result is None:
            return f"Tool {tool_name} returned no data."

        try:
            if isinstance(result, dict) and "content" in result:
                content = result["content"]
                if isinstance(content, list):
                    texts = []
                    for item in content:
                        if isinstance(item, dict) and item.get("type") == "text":
                            text = item.get("text", "")
                            if isinstance(text, str):
                                try:
                                    parsed = json.loads(text)
                                    texts.append(json.dumps(parsed, indent=2))
                                except json.JSONDecodeError:
                                    texts.append(text)
                            else:
                                texts.append(json.dumps(text, indent=2))
                    if texts:
                        return f"**{tool_name} Result:**\n```json\n{chr(10).join(texts)}\n```"

            formatted = json.dumps(result, indent=2)
            return f"**{tool_name} Result:**\n```json\n{formatted}\n```"
        except Exception:
            return f"Tool {tool_name} result: {result}"
