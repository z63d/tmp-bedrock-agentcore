/**
 * New Relic MCP Proxy Lambda Handler
 * Implements MCP Protocol 2025-03-26
 *
 * This Lambda function acts as a proxy to New Relic's Remote MCP Server,
 * enabling AI agents to access New Relic observability data via AgentCore Gateway.
 */

import { getApiKey, getMcpEndpoint } from "./config.js";
import { getToolDefinitions } from "./tools/index.js";
import { createMcpClient } from "./proxy/mcp-client.js";
import {
  LambdaContext,
  JsonRpcRequest,
  NewRelicMcpError,
  HttpError,
} from "./types/index.js";

// MCP Protocol version
const MCP_PROTOCOL_VERSION = "2025-03-26";

/**
 * Create a JSON-RPC success response
 */
function mcpResponse(
  requestId: string | number,
  result: unknown
): Record<string, unknown> {
  return {
    jsonrpc: "2.0",
    id: requestId,
    result,
  };
}

/**
 * Create a JSON-RPC error response
 */
function mcpError(
  requestId: string | number,
  code: number,
  message: string
): Record<string, unknown> {
  return {
    jsonrpc: "2.0",
    id: requestId,
    error: {
      code,
      message,
    },
  };
}

/**
 * Handle MCP initialize request
 */
function handleInitialize(): Record<string, unknown> {
  return {
    protocolVersion: MCP_PROTOCOL_VERSION,
    capabilities: {
      tools: {},
    },
    serverInfo: {
      name: "newrelic-mcp-proxy",
      version: "1.0.0",
    },
  };
}

/**
 * Extract tool name from Gateway Target context
 * Gateway passes tool name in context.clientContext.custom.bedrockAgentCoreToolName
 * Format: {target_name}___{tool_name}
 */
function extractToolNameFromContext(context: LambdaContext): string | null {
  const custom = context.clientContext?.custom;
  if (!custom) return null;

  const fullToolName = custom.bedrockAgentCoreToolName;
  if (!fullToolName) return null;

  // Strip target name prefix: {target_name}___{tool_name}
  const delimiter = "___";
  if (fullToolName.includes(delimiter)) {
    return fullToolName.split(delimiter).pop() || null;
  }

  return fullToolName;
}

/**
 * Get include-tags from environment variable
 */
function getIncludeTags(): string[] | undefined {
  const tags = process.env.NEWRELIC_MCP_INCLUDE_TAGS;
  if (!tags) return undefined;
  return tags.split(",").map((t) => t.trim()).filter(Boolean);
}

/**
 * Get default account ID from environment variable
 */
function getDefaultAccountId(): string | undefined {
  const accountId = process.env.NEWRELIC_DEFAULT_ACCOUNT_ID;
  if (!accountId || accountId.trim() === "") return undefined;
  return accountId.trim();
}

/**
 * Convert camelCase to snake_case
 * New Relic MCP uses snake_case for parameter names
 */
function camelToSnake(str: string): string {
  return str.replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`);
}

/**
 * Convert all keys in an object from camelCase to snake_case
 */
function convertKeysToSnakeCase(
  obj: Record<string, unknown>
): Record<string, unknown> {
  const result: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(obj)) {
    const snakeKey = camelToSnake(key);
    result[snakeKey] = value;
  }
  return result;
}

/**
 * Proxy a tool call to New Relic's Remote MCP Server
 */
async function proxyToolCall(
  toolName: string,
  args: Record<string, unknown>
): Promise<unknown> {
  const apiKey = await getApiKey();
  const endpoint = getMcpEndpoint();
  const includeTags = getIncludeTags();

  const client = createMcpClient(endpoint, apiKey, includeTags);

  // Convert camelCase keys to snake_case for New Relic MCP
  const snakeCaseArgs = convertKeysToSnakeCase(args);

  // Apply default account_id if not provided
  const defaultAccountId = getDefaultAccountId();
  if (defaultAccountId && !snakeCaseArgs.account_id) {
    snakeCaseArgs.account_id = parseInt(defaultAccountId, 10);
    console.log(`Using default account_id: ${defaultAccountId}`);
  }

  try {
    const result = await client.callTool(toolName, snakeCaseArgs);

    // Extract text content if available
    if (result.content && result.content.length > 0) {
      const textContent = result.content.find((c) => c.type === "text");
      if (textContent?.text) {
        try {
          return JSON.parse(textContent.text);
        } catch {
          return textContent.text;
        }
      }
    }

    return result;
  } catch (error) {
    if (error instanceof NewRelicMcpError) {
      console.error(`New Relic MCP error: ${error.code} ${error.message}`);
      throw error;
    }
    if (error instanceof HttpError) {
      console.error(`HTTP error: ${error.status} ${error.message}`);
      throw error;
    }
    throw error;
  }
}

/**
 * Lambda handler entry point
 *
 * Supports two invocation patterns:
 * 1. Gateway Target invocation (from AgentCore Gateway):
 *    - Event: Tool arguments directly (e.g., {"accountId": 12345, "query": "..."})
 *    - Context: clientContext.custom contains tool metadata including bedrockAgentCoreToolName
 *
 * 2. API Gateway / Direct invocation (JSON-RPC format):
 *    - Event: {"body": "{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",...}"}
 */
export async function handler(
  event: Record<string, unknown>,
  context: LambdaContext
): Promise<string | Record<string, unknown>> {
  try {
    // Log for debugging
    console.log("Raw event:", JSON.stringify(event).slice(0, 2000));

    // Check if this is a Gateway Target invocation
    const toolNameFromContext = extractToolNameFromContext(context);

    if (toolNameFromContext) {
      // Gateway Target: Proxy tool call to New Relic MCP
      console.log(`Gateway Target invocation: tool=${toolNameFromContext}`);
      console.log(
        `Proxying tool '${toolNameFromContext}' with args:`,
        JSON.stringify(event).slice(0, 500)
      );

      const result = await proxyToolCall(
        toolNameFromContext,
        event as Record<string, unknown>
      );

      // Return result as plain JSON string (not wrapped in JSON-RPC)
      return JSON.stringify(result);
    }

    // API Gateway / Direct invocation: JSON-RPC format
    let body: JsonRpcRequest;

    if ("body" in event && typeof event.body === "string") {
      body = JSON.parse(event.body) as JsonRpcRequest;
    } else {
      body = event as unknown as JsonRpcRequest;
    }

    const method = body.method;
    const params = body.params || {};
    const requestId = body.id || 1;

    console.log(
      `MCP Request: method=${method}, params=${JSON.stringify(params).slice(0, 500)}`
    );

    if (method === "initialize") {
      return mcpResponse(requestId, handleInitialize());
    }

    if (method === "tools/list") {
      // Return locally defined tools
      // Note: Could also proxy to New Relic MCP for dynamic tool list
      return mcpResponse(requestId, { tools: getToolDefinitions() });
    }

    if (method === "tools/call") {
      const toolName = params.name as string;
      const args = (params.arguments as Record<string, unknown>) || {};

      const result = await proxyToolCall(toolName, args);

      return mcpResponse(requestId, {
        content: [
          {
            type: "text",
            text: JSON.stringify(result),
          },
        ],
      });
    }

    return mcpError(requestId, -32601, `Method not found: ${method}`);
  } catch (error) {
    console.error("Handler error:", error);

    if (error instanceof SyntaxError) {
      return mcpError(1, -32700, `Parse error: ${error.message}`);
    }

    if (error instanceof NewRelicMcpError) {
      return mcpError(1, error.code, `New Relic MCP: ${error.message}`);
    }

    if (error instanceof HttpError) {
      return mcpError(1, -32000, `HTTP error ${error.status}: ${error.message}`);
    }

    const errorMessage =
      error instanceof Error ? error.message : "Unknown error";
    return mcpError(1, -32603, `Internal error: ${errorMessage}`);
  }
}
