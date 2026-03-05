/**
 * CloudWatch MCP Gateway Client
 *
 * This client calls AgentCore Gateway with MCP protocol
 * to execute CloudWatch tools via JSON-RPC.
 *
 * Reference: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/gateway-using-mcp-call.html
 */

export interface CloudWatchClientConfig {
  region: string;
  gatewayId: string;
}

export interface CloudWatchResponse {
  text: string;
  toolResults?: ToolExecutionResult[];
}

export interface ToolExecutionResult {
  toolName: string;
  input: Record<string, unknown>;
  output: unknown;
}

interface MCPToolInfo {
  name: string;
  description?: string;
  inputSchema?: unknown;
}

/**
 * CloudWatch client using AgentCore Gateway with MCP protocol.
 *
 * Gateway URL format: https://{gateway-id}.gateway.bedrock-agentcore.{region}.amazonaws.com/mcp
 */
export class CloudWatchResponsesClient {
  private region: string;
  private gatewayEndpoint: string;

  constructor(config: CloudWatchClientConfig) {
    this.region = config.region;
    this.gatewayEndpoint = `https://${config.gatewayId}.gateway.bedrock-agentcore.${config.region}.amazonaws.com/mcp`;
  }

  /**
   * List available tools from the gateway.
   */
  async listTools(): Promise<MCPToolInfo[]> {
    const response = await this.sendMCPRequest("tools/list", {});
    const result = response as { tools?: MCPToolInfo[] };
    return result.tools ?? [];
  }

  /**
   * Call a specific tool via the gateway.
   */
  async callTool(
    toolName: string,
    args: Record<string, unknown>
  ): Promise<unknown> {
    const response = await this.sendMCPRequest("tools/call", {
      name: toolName,
      arguments: args,
    });
    return response;
  }

  /**
   * Invoke the CloudWatch agent with a natural language prompt.
   * This method lists tools and calls the appropriate one based on the prompt.
   */
  async invoke(prompt: string): Promise<CloudWatchResponse> {
    console.log(`CloudWatch MCP Gateway invoke: ${prompt}`);

    try {
      // First, list available tools
      const tools = await this.listTools();
      console.log(
        `Available tools:`,
        tools.map((t) => t.name)
      );

      // Determine which tool to call based on prompt
      const toolToCall = this.selectToolForPrompt(prompt, tools);

      if (!toolToCall) {
        return {
          text: `No matching CloudWatch tool found for the request. Available tools: ${tools.map((t) => t.name).join(", ")}`,
          toolResults: [],
        };
      }

      // Build arguments based on tool and prompt
      const toolArgs = this.buildToolArguments(toolToCall, prompt);

      console.log(`Calling tool: ${toolToCall.name} with args:`, toolArgs);

      // Call the tool
      const toolResult = await this.callTool(toolToCall.name, toolArgs);

      console.log(`Tool result:`, JSON.stringify(toolResult, null, 2));

      return {
        text: this.formatToolResult(toolToCall.name, toolResult),
        toolResults: [
          {
            toolName: toolToCall.name,
            input: toolArgs,
            output: toolResult,
          },
        ],
      };
    } catch (error) {
      console.error(`CloudWatch MCP error:`, error);
      throw error;
    }
  }

  /**
   * Send a JSON-RPC request to the MCP Gateway.
   */
  private async sendMCPRequest(
    method: string,
    params: Record<string, unknown>
  ): Promise<unknown> {
    const { SignatureV4 } = await import("@smithy/signature-v4");
    const { Sha256 } = await import("@aws-crypto/sha256-js");
    const { fromNodeProviderChain } = await import(
      "@aws-sdk/credential-providers"
    );

    const credentials = await fromNodeProviderChain()();

    const requestBody = {
      jsonrpc: "2.0",
      id: `request-${Date.now()}`,
      method,
      params,
    };

    const url = new URL(this.gatewayEndpoint);

    const signer = new SignatureV4({
      service: "bedrock-agentcore",
      region: this.region,
      credentials,
      sha256: Sha256,
    });

    const request = {
      method: "POST",
      protocol: "https:",
      hostname: url.hostname,
      path: url.pathname,
      headers: {
        "Content-Type": "application/json",
        host: url.hostname,
      },
      body: JSON.stringify(requestBody),
    };

    console.log(`MCP Request to ${this.gatewayEndpoint}:`, requestBody);

    const signedRequest = await signer.sign(request);

    const response = await fetch(url.toString(), {
      method: signedRequest.method,
      headers: signedRequest.headers as HeadersInit,
      body: signedRequest.body,
    });

    const responseText = await response.text();
    console.log(`MCP Response (${response.status}):`, responseText);

    if (!response.ok) {
      throw new Error(`MCP Gateway error: ${response.status} - ${responseText}`);
    }

    const result = JSON.parse(responseText);

    // JSON-RPC response handling
    if (result.error) {
      throw new Error(
        `MCP error: ${result.error.message ?? JSON.stringify(result.error)}`
      );
    }

    return result.result;
  }

  /**
   * Extract the base tool name from Gateway's prefixed format.
   * Gateway returns tools as: {target-name}___{tool-name}
   */
  private getBaseToolName(fullName: string): string {
    const parts = fullName.split("___");
    return parts.length > 1 ? parts[parts.length - 1] : fullName;
  }

  /**
   * Select the appropriate tool based on the prompt.
   */
  private selectToolForPrompt(
    prompt: string,
    tools: MCPToolInfo[]
  ): MCPToolInfo | null {
    const lowerPrompt = prompt.toLowerCase();

    // Keyword to tool mapping (using base tool names)
    const toolKeywords: Record<string, string[]> = {
      get_active_alarms: ["alarm", "alert", "アラーム", "発報"],
      get_alarm_history: ["alarm history", "アラーム履歴"],
      get_metric_data: ["metric", "メトリクス", "cpu", "memory", "utilization"],
      analyze_metric: ["analyze", "trend", "分析", "傾向"],
      describe_log_groups: ["log group", "ロググループ", "list log"],
      analyze_log_group: ["log", "error", "ログ", "エラー"],
      execute_log_insights_query: ["insights", "query", "クエリ"],
    };

    for (const tool of tools) {
      // Check both full name and base name
      const baseName = this.getBaseToolName(tool.name);
      const keywords = toolKeywords[baseName] ?? toolKeywords[tool.name];
      if (keywords?.some((kw) => lowerPrompt.includes(kw))) {
        return tool;
      }
    }

    // Default to listing alarms if no specific match
    const defaultTool = tools.find((t) => {
      const baseName = this.getBaseToolName(t.name);
      return baseName === "get_active_alarms" || t.name === "get_active_alarms";
    });
    return defaultTool ?? tools[0] ?? null;
  }

  /**
   * Build tool arguments based on the tool and prompt.
   */
  private buildToolArguments(
    tool: MCPToolInfo,
    _prompt: string
  ): Record<string, unknown> {
    // Use base tool name for matching
    const baseName = this.getBaseToolName(tool.name);

    // Basic default arguments per tool
    switch (baseName) {
      case "get_active_alarms":
        return { state_value: "ALARM" };
      case "get_metric_data":
        return {
          namespace: "AWS/EC2",
          metric_name: "CPUUtilization",
          period: 300,
          stat: "Average",
        };
      case "describe_log_groups":
        return { limit: 10 };
      case "analyze_log_group":
        return { hours: 1 };
      default:
        return {};
    }
  }

  /**
   * Format tool result into human-readable text.
   */
  private formatToolResult(toolName: string, result: unknown): string {
    if (result === null || result === undefined) {
      return `Tool ${toolName} returned no data.`;
    }

    try {
      // MCP response format: { isError: boolean, content: [{ type: "text", text: ... }] }
      const mcpResult = result as {
        isError?: boolean;
        content?: Array<{ type: string; text: unknown }>;
      };

      if (mcpResult.content && Array.isArray(mcpResult.content)) {
        const texts = mcpResult.content
          .filter((c) => c.type === "text")
          .map((c) => {
            // text might be a string or an object
            if (typeof c.text === "string") {
              // Try to parse if it's JSON string
              try {
                const parsed = JSON.parse(c.text);
                return JSON.stringify(parsed, null, 2);
              } catch {
                return c.text;
              }
            }
            return JSON.stringify(c.text, null, 2);
          });

        if (texts.length > 0) {
          return `**${toolName} Result:**\n\`\`\`json\n${texts.join("\n")}\n\`\`\``;
        }
      }

      // Fallback: stringify the entire result
      const formatted = JSON.stringify(result, null, 2);
      return `**${toolName} Result:**\n\`\`\`json\n${formatted}\n\`\`\``;
    } catch {
      return `Tool ${toolName} result: ${String(result)}`;
    }
  }
}
