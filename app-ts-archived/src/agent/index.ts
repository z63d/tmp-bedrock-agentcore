import { Agent, BedrockModel, tool, McpClient } from "@strands-agents/sdk";
import { z } from "zod";

// カスタムツール: 計算機
const calculatorSchema = z.object({
  operation: z
    .enum(["add", "subtract", "multiply", "divide"])
    .describe("The mathematical operation to perform"),
  a: z.number().describe("First number"),
  b: z.number().describe("Second number"),
});

const calculator = tool({
  name: "calculator",
  description: "Perform mathematical calculations",
  inputSchema: calculatorSchema,
  callback: (input) => {
    switch (input.operation) {
      case "add":
        return `Result: ${input.a} + ${input.b} = ${input.a + input.b}`;
      case "subtract":
        return `Result: ${input.a} - ${input.b} = ${input.a - input.b}`;
      case "multiply":
        return `Result: ${input.a} * ${input.b} = ${input.a * input.b}`;
      case "divide":
        return `Result: ${input.a} / ${input.b} = ${input.a / input.b}`;
    }
  },
});

/**
 * Agent configuration options
 */
export interface AgentConfig {
  /** MCP client for Gateway integration */
  mcpClient?: McpClient;
  /** System prompt override */
  systemPrompt?: string;
}

/**
 * Create an agent with optional MCP tools
 *
 * @param config Agent configuration
 * @returns Configured Agent instance
 */
export async function createAgent(config: AgentConfig = {}): Promise<Agent> {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const tools: any[] = [calculator];

  // Add MCP client if provided - SDK handles tool discovery automatically
  if (config.mcpClient) {
    tools.push(config.mcpClient);
  }

  // Build system prompt
  const systemPrompt =
    config.systemPrompt ?? buildSystemPrompt(!!config.mcpClient);

  return new Agent({
    model: new BedrockModel({
      region: process.env.AWS_REGION ?? "ap-northeast-1",
      modelId:
        process.env.BEDROCK_MODEL_ID ?? "anthropic.claude-3-haiku-20240307-v1:0",
      maxTokens: 4096,
    }),
    tools,
    systemPrompt,
  });
}

/**
 * Build system prompt based on available tools
 */
function buildSystemPrompt(hasMcpTools: boolean): string {
  const basePrompt = "You are a helpful assistant.";

  const toolInstructions: string[] = [
    "When asked to perform calculations, use the calculator tool.",
  ];

  if (hasMcpTools) {
    toolInstructions.push(
      "For Rollbar error tracking queries (items, deployments, versions, errors, bugs, incidents), use the Rollbar tools.",
      "For CloudWatch monitoring queries (alarms, metrics, logs), use the CloudWatch tools."
    );
  }

  return `${basePrompt}\n\n${toolInstructions.join("\n")}`;
}

/**
 * Create a default agent without MCP tools (for backward compatibility)
 */
export async function createDefaultAgent(): Promise<Agent> {
  return createAgent();
}
