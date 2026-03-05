import { Agent, BedrockModel, tool } from "@strands-agents/sdk";
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

// Agent作成
export const agent = new Agent({
  model: new BedrockModel({
    region: process.env.AWS_REGION ?? "ap-northeast-1",
    modelId:
      process.env.BEDROCK_MODEL_ID ?? "anthropic.claude-3-haiku-20240307-v1:0",
    maxTokens: 4096,
  }),
  tools: [calculator],
  systemPrompt:
    "You are a helpful assistant. When asked to perform calculations, use the calculator tool.",
});
