/**
 * New Relic Remote MCP Client
 * Proxies MCP requests to New Relic's hosted MCP server
 */

import {
  JsonRpcRequest,
  JsonRpcResponse,
  JsonRpcErrorResponse,
  McpToolDefinition,
  McpToolCallResult,
  McpInitializeResult,
  NewRelicMcpError,
  HttpError,
} from "../types/index.js";

// HTTP timeout (55 seconds, slightly less than Lambda's 60s timeout)
const HTTP_TIMEOUT_MS = 55000;

/**
 * New Relic MCP Client configuration
 */
export interface NewRelicMcpClientConfig {
  endpoint: string;
  apiKey: string;
  includeTags?: string[];
}

/**
 * Client for communicating with New Relic's Remote MCP Server
 */
export class NewRelicMcpClient {
  private readonly endpoint: string;
  private readonly apiKey: string;
  private readonly includeTags?: string[];
  private requestId = 0;

  constructor(config: NewRelicMcpClientConfig) {
    this.endpoint = config.endpoint;
    this.apiKey = config.apiKey;
    this.includeTags = config.includeTags;
  }

  /**
   * Generate a unique request ID
   */
  private nextRequestId(): number {
    return ++this.requestId;
  }

  /**
   * Build request headers
   */
  private buildHeaders(): Record<string, string> {
    const headers: Record<string, string> = {
      "Content-Type": "application/json",
      "Accept": "application/json",
      "Api-Key": this.apiKey,
    };

    if (this.includeTags && this.includeTags.length > 0) {
      headers["include-tags"] = this.includeTags.join(",");
    }

    return headers;
  }

  /**
   * Send a JSON-RPC request to New Relic MCP
   */
  private async sendRequest<T>(
    method: string,
    params?: Record<string, unknown>
  ): Promise<T> {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), HTTP_TIMEOUT_MS);

    const request: JsonRpcRequest = {
      jsonrpc: "2.0",
      id: this.nextRequestId(),
      method,
      params,
    };

    try {
      console.log(`Sending MCP request: method=${method}`);

      const response = await fetch(this.endpoint, {
        method: "POST",
        headers: this.buildHeaders(),
        body: JSON.stringify(request),
        signal: controller.signal,
      });

      clearTimeout(timeoutId);

      if (!response.ok) {
        const errorText = await response.text();
        console.error(`HTTP error: ${response.status} ${errorText}`);
        throw new HttpError(response.status, errorText || response.statusText);
      }

      const data = await response.json() as JsonRpcResponse<T> | JsonRpcErrorResponse;

      if ("error" in data) {
        console.error(`MCP error: ${data.error.code} ${data.error.message}`);
        throw new NewRelicMcpError(
          data.error.code,
          data.error.message,
          data.error.data
        );
      }

      return data.result;
    } catch (error) {
      clearTimeout(timeoutId);

      if (error instanceof Error && error.name === "AbortError") {
        throw new HttpError(504, "Request timeout");
      }

      throw error;
    }
  }

  /**
   * Initialize the MCP session
   */
  async initialize(): Promise<McpInitializeResult> {
    return this.sendRequest<McpInitializeResult>("initialize", {
      protocolVersion: "2025-03-26",
      capabilities: {},
      clientInfo: {
        name: "newrelic-mcp-lambda-proxy",
        version: "1.0.0",
      },
    });
  }

  /**
   * List available tools from New Relic MCP
   */
  async listTools(): Promise<McpToolDefinition[]> {
    const result = await this.sendRequest<{ tools: McpToolDefinition[] }>("tools/list");
    return result.tools;
  }

  /**
   * Call a tool on New Relic MCP
   */
  async callTool(
    name: string,
    args: Record<string, unknown>
  ): Promise<McpToolCallResult> {
    console.log(`Calling tool: ${name} with args:`, JSON.stringify(args).slice(0, 500));

    const result = await this.sendRequest<McpToolCallResult>("tools/call", {
      name,
      arguments: args,
    });

    return result;
  }
}

/**
 * Create a New Relic MCP client with the given configuration
 */
export function createMcpClient(
  endpoint: string,
  apiKey: string,
  includeTags?: string[]
): NewRelicMcpClient {
  return new NewRelicMcpClient({
    endpoint,
    apiKey,
    includeTags,
  });
}
