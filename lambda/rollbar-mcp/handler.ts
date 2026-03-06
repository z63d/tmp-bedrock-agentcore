/**
 * Rollbar MCP Server Handler for AWS Lambda
 * Implements MCP Protocol 2025-03-26
 *
 * This Lambda function provides Rollbar error tracking tools via the MCP protocol,
 * enabling AI agents to query items, deployments, and session replays.
 */

import { getAccessToken } from "./config.js";
import { getToolDefinitions, executeTool } from "./tools/index.js";

// MCP Protocol version
const MCP_PROTOCOL_VERSION = "2025-03-26";

/**
 * Lambda context type with optional clientContext from AgentCore Gateway
 */
interface LambdaContext {
  clientContext?: {
    custom?: {
      bedrockAgentCoreToolName?: string;
      [key: string]: unknown;
    };
    [key: string]: unknown;
  };
  [key: string]: unknown;
}

/**
 * JSON-RPC request body
 */
interface JsonRpcRequest {
  jsonrpc: string;
  id: string | number;
  method: string;
  params?: Record<string, unknown>;
}

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
      name: "rollbar-mcp-server",
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
 * Lambda handler entry point
 *
 * Supports two invocation patterns:
 * 1. Gateway Target invocation (from AgentCore Gateway):
 *    - Event: Tool arguments directly (e.g., {"environment": "production"})
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
      // Gateway Target: Execute tool directly
      console.log(`Gateway Target invocation: tool=${toolNameFromContext}`);
      console.log(
        `Executing tool '${toolNameFromContext}' with args:`,
        JSON.stringify(event).slice(0, 500)
      );

      const accessToken = await getAccessToken();
      const result = await executeTool(
        toolNameFromContext,
        event as Record<string, unknown>,
        accessToken
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
      return mcpResponse(requestId, { tools: getToolDefinitions() });
    }

    if (method === "tools/call") {
      const toolName = params.name as string;
      const args = (params.arguments as Record<string, unknown>) || {};

      const accessToken = await getAccessToken();
      const result = await executeTool(toolName, args, accessToken);

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

    const errorMessage =
      error instanceof Error ? error.message : "Unknown error";
    return mcpError(1, -32603, `Internal error: ${errorMessage}`);
  }
}
