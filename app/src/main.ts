import { BedrockAgentCoreApp } from "bedrock-agentcore/runtime";
import { z } from "zod";
import { agent } from "./agent/index.js";
import { AgentCoreMemoryClient } from "./memory/client.js";
import { CloudWatchResponsesClient } from "./responses-api/index.js";

const region = process.env.AWS_REGION ?? "ap-northeast-1";
const memoryId = process.env.MEMORY_ID;
const gatewayArn = process.env.GATEWAY_ARN;

// Initialize Memory Client (optional)
const memoryClient = memoryId
  ? new AgentCoreMemoryClient({ region, memoryId })
  : null;

if (memoryClient) {
  console.log(`Memory enabled with ID: ${memoryId}`);
} else {
  console.log("Memory disabled (MEMORY_ID not set)");
}

// Initialize CloudWatch Client (optional)
// Extract gatewayId from ARN: arn:aws:bedrock-agentcore:{region}:{account}:gateway/{gatewayId}
const gatewayId = gatewayArn?.split("/").pop();
const cloudwatchClient = gatewayId
  ? new CloudWatchResponsesClient({ region, gatewayId })
  : null;

if (cloudwatchClient) {
  console.log(`CloudWatch MCP enabled with Gateway ARN: ${gatewayArn}`);
} else {
  console.log("CloudWatch MCP disabled (GATEWAY_ARN not set)");
}

// Request schema for agent invocation
const requestSchema = z.object({
  prompt: z.string(),
  sessionId: z.string(),
});

const app = new BedrockAgentCoreApp({
  invocationHandler: {
    requestSchema,
    process: async function* (request, _context) {
      const { prompt, sessionId } = request;
      const actorId = "user";

      console.log(`Session ${sessionId} - Received prompt:`, prompt);

      // Check if this is a CloudWatch-related query
      const isCloudWatchQuery = isCloudWatchRelatedPrompt(prompt);
      console.log(`CloudWatch query detection: ${isCloudWatchQuery}, cloudwatchClient available: ${!!cloudwatchClient}`);

      if (isCloudWatchQuery && cloudwatchClient) {
        // Route to CloudWatch agent
        console.log("Routing to CloudWatch agent...");
        try {
          const cloudwatchResponse = await cloudwatchClient.invoke(prompt);

          // Log tool usage if any
          if (cloudwatchResponse.toolResults?.length) {
            console.log(
              `CloudWatch tools used: ${cloudwatchResponse.toolResults
                .map((t) => t.toolName)
                .join(", ")}`
            );
          }

          // Store in memory if available
          if (memoryClient) {
            try {
              await memoryClient.createEvent(actorId, sessionId, [
                { role: "USER", content: prompt },
                { role: "ASSISTANT", content: cloudwatchResponse.text },
              ]);
            } catch (error) {
              console.warn("Failed to store CloudWatch conversation:", error);
            }
          }

          yield {
            event: "message",
            data: {
              text: cloudwatchResponse.text,
              sessionId,
              agent: "cloudwatch",
            },
          };
          return;
        } catch (error) {
          console.error("CloudWatch agent error:", error);
          // Fall back to standard agent
        }
      }

      // Standard agent flow
      let contextPrompt = prompt;

      // Retrieve relevant memories if available
      if (memoryClient) {
        try {
          const memories = await memoryClient.searchMemories(prompt, "/", 3);
          if (memories.length > 0) {
            const memoryContext = memories
              .map((m) => m.content?.text)
              .filter(Boolean)
              .join("\n");
            if (memoryContext) {
              contextPrompt = `[Previous context]\n${memoryContext}\n\n[Current question]\n${prompt}`;
              console.log(`Found ${memories.length} relevant memories`);
            }
          }
        } catch (error) {
          console.warn("Failed to retrieve memories:", error);
        }
      }

      // Invoke standard agent
      const result = await agent.invoke(contextPrompt);
      const response = result.toString();

      // Store conversation in memory
      if (memoryClient) {
        try {
          await memoryClient.createEvent(actorId, sessionId, [
            { role: "USER", content: prompt },
            { role: "ASSISTANT", content: response },
          ]);
          console.log("Conversation stored in memory");
        } catch (error) {
          console.warn("Failed to store conversation:", error);
        }
      }

      // Yield response using streaming pattern
      yield { event: "message", data: { text: response, sessionId } };
    },
  },
});

/**
 * Determine if a prompt is related to CloudWatch observability queries.
 * This enables automatic routing to the CloudWatch agent.
 */
function isCloudWatchRelatedPrompt(prompt: string): boolean {
  const cloudwatchKeywords = [
    // Metrics
    "metric",
    "cpu",
    "memory usage",
    "utilization",
    "latency",
    "throughput",
    "invocation",
    "duration",
    "error rate",
    // Alarms (English and Japanese)
    "alarm",
    "alert",
    "threshold",
    "trigger",
    "notification",
    "アラーム",
    "アラート",
    "発報",
    "通知",
    // Logs (English and Japanese)
    "log",
    "error",
    "exception",
    "trace",
    "debug",
    "warning",
    "log group",
    "log insights",
    "ログ",
    "エラー",
    // CloudWatch specific
    "cloudwatch",
    "monitoring",
    "observability",
    "dashboard",
    "mcp",
    // AWS services often monitored
    "ec2",
    "lambda",
    "rds",
    "ecs",
    "api gateway",
    "dynamodb",
    "sqs",
    "sns",
    // Actions (English and Japanese)
    "analyze",
    "trend",
    "pattern",
    "anomaly",
    "spike",
    "drop",
    "分析",
    "傾向",
    "パターン",
    "異常",
    // Japanese CloudWatch keywords
    "メトリクス",
    "メトリック",
    "監視",
    "観測",
  ];

  const lowerPrompt = prompt.toLowerCase();
  return cloudwatchKeywords.some((keyword) => lowerPrompt.includes(keyword.toLowerCase()));
}

console.log("Starting AgentCore Runtime server on port 8080...");
app.run();
