import { getToolDefinitions, executeTool } from "./tools/index.js";

const MCP_PROTOCOL_VERSION = "2025-03-26";

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

interface JsonRpcRequest {
  jsonrpc: string;
  id: string | number;
  method: string;
  params?: Record<string, unknown>;
}

function mcpResponse(requestId: string | number, result: unknown) {
  return { jsonrpc: "2.0", id: requestId, result };
}

function mcpError(requestId: string | number, code: number, message: string) {
  return { jsonrpc: "2.0", id: requestId, error: { code, message } };
}

function extractToolNameFromContext(context: LambdaContext): string | null {
  const fullToolName = context.clientContext?.custom?.bedrockAgentCoreToolName;
  if (!fullToolName) return null;
  const delimiter = "___";
  return fullToolName.includes(delimiter)
    ? fullToolName.split(delimiter).pop() || null
    : fullToolName;
}

export async function handler(
  event: Record<string, unknown>,
  context: LambdaContext
): Promise<string | Record<string, unknown>> {
  try {
    console.log("Raw event:", JSON.stringify(event).slice(0, 2000));

    const toolNameFromContext = extractToolNameFromContext(context);

    if (toolNameFromContext) {
      console.log(`Gateway Target invocation: tool=${toolNameFromContext}`, JSON.stringify(event).slice(0, 500));
      const result = await executeTool(toolNameFromContext, event);
      return JSON.stringify(result);
    }

    let body: JsonRpcRequest;
    if ("body" in event && typeof event.body === "string") {
      body = JSON.parse(event.body) as JsonRpcRequest;
    } else {
      body = event as unknown as JsonRpcRequest;
    }

    const method = body.method;
    const params = body.params || {};
    const requestId = body.id || 1;

    console.log(`MCP Request: method=${method}`);

    if (method === "initialize") {
      return mcpResponse(requestId, {
        protocolVersion: MCP_PROTOCOL_VERSION,
        capabilities: { tools: {} },
        serverInfo: { name: "slack-ext-mcp-server", version: "1.0.0" },
      });
    }

    if (method === "tools/list") {
      return mcpResponse(requestId, { tools: getToolDefinitions() });
    }

    if (method === "tools/call") {
      const toolName = params.name as string;
      const args = (params.arguments as Record<string, unknown>) || {};
      const result = await executeTool(toolName, args);
      return mcpResponse(requestId, {
        content: [{ type: "text", text: JSON.stringify(result) }],
      });
    }

    return mcpError(requestId, -32601, `Method not found: ${method}`);
  } catch (error) {
    console.error("Handler error:", error);
    if (error instanceof SyntaxError) {
      return mcpError(1, -32700, `Parse error: ${error.message}`);
    }
    const msg = error instanceof Error ? error.message : "Unknown error";
    return mcpError(1, -32603, `Internal error: ${msg}`);
  }
}
