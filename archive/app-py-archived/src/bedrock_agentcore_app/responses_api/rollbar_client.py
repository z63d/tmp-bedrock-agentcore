"""Rollbar MCP Gateway Client for JSON-RPC tool invocation."""

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


class RollbarResponse(BaseModel):
    """Response from Rollbar tool invocation."""

    text: str
    tool_results: list[ToolExecutionResult] = []


class MCPToolInfo(BaseModel):
    """Information about an MCP tool."""

    name: str
    description: str | None = None
    input_schema: dict[str, Any] | None = None


class RollbarResponsesClient:
    """
    Rollbar client using AgentCore Gateway with MCP protocol.

    Gateway URL format: https://{gateway-id}.gateway.bedrock-agentcore.{region}.amazonaws.com/mcp
    """

    # Keyword to tool mapping (bilingual: English and Japanese)
    TOOL_KEYWORDS: dict[str, list[str]] = {
        "get-item-details": [
            "item",
            "counter",
            "アイテム",
            "詳細",
            "occurrence",
            "オカレンス",
        ],
        "get-deployments": [
            "deploy",
            "release",
            "デプロイ",
            "リリース",
            "deployment",
        ],
        "get-version": ["version", "バージョン", "sha", "commit"],
        "get-top-items": [
            "top",
            "active",
            "トップ",
            "上位",
            "most",
            "frequent",
        ],
        "list-items": [
            "list",
            "search",
            "filter",
            "一覧",
            "検索",
            "items",
            "errors",
        ],
        "update-item": [
            "update",
            "status",
            "resolve",
            "更新",
            "ステータス",
            "mute",
            "archive",
        ],
        "get-replay": [
            "replay",
            "session",
            "リプレイ",
            "セッション",
            "recording",
        ],
    }

    def __init__(self, region: str, gateway_id: str) -> None:
        """
        Initialize the Rollbar client.

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

    async def invoke(self, prompt: str) -> RollbarResponse:
        """
        Invoke the Rollbar agent with a natural language prompt.

        Args:
            prompt: Natural language prompt

        Returns:
            RollbarResponse with formatted result
        """
        logger.info("Rollbar MCP Gateway invoke", prompt=prompt[:100])

        try:
            tools = await self.list_tools()
            logger.info("Available tools", tools=[t.name for t in tools])

            tool_to_call = self._select_tool_for_prompt(prompt, tools)

            if not tool_to_call:
                return RollbarResponse(
                    text=f"No matching Rollbar tool found. Available tools: {', '.join(t.name for t in tools)}",
                    tool_results=[],
                )

            tool_args = self._build_tool_arguments(tool_to_call, prompt)
            logger.info("Calling tool", tool=tool_to_call.name, args=tool_args)

            tool_result = await self.call_tool(tool_to_call.name, tool_args)
            logger.info("Tool result received", tool=tool_to_call.name)

            return RollbarResponse(
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
            logger.error("Rollbar MCP error", error=str(e))
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

        # Default to get-top-items
        default_tool = next(
            (
                t
                for t in tools
                if self._get_base_tool_name(t.name) == "get-top-items"
            ),
            None,
        )
        return default_tool or (tools[0] if tools else None)

    def _build_tool_arguments(
        self,
        tool: MCPToolInfo,
        prompt: str,
    ) -> dict[str, Any]:
        """Build tool arguments based on the tool type and prompt content."""
        base_name = self._get_base_tool_name(tool.name)

        # Extract counter/item number from prompt
        counter_match = re.search(r"(?:counter|item|#)\s*(\d+)", prompt, re.IGNORECASE)
        counter = int(counter_match.group(1)) if counter_match else None

        match base_name:
            case "get-item-details":
                return {"counter": counter or 1}
            case "get-deployments":
                return {"limit": 10}
            case "get-version":
                version_match = re.search(
                    r"(?:version|sha|commit)\s*[:\s]?\s*([a-f0-9]{7,40})",
                    prompt,
                    re.IGNORECASE,
                )
                return {"version": version_match.group(1) if version_match else "latest"}
            case "get-top-items":
                return {"environment": "production"}
            case "list-items":
                return {"status": "active", "environment": "production", "limit": 20}
            case "update-item":
                item_id_match = re.search(
                    r"(?:item|id)\s*[:\s]?\s*(\d+)", prompt, re.IGNORECASE
                )
                status_match = re.search(
                    r"(resolve|mute|archive|active)", prompt, re.IGNORECASE
                )
                args: dict[str, Any] = {}
                if item_id_match:
                    args["itemId"] = int(item_id_match.group(1))
                if status_match:
                    args["status"] = status_match.group(1).lower()
                return args
            case "get-replay":
                return {"environment": "production"}
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
