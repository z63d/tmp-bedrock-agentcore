import type { Agent } from "@strands-agents/sdk";
import { BedrockAgentCoreApp } from "bedrock-agentcore/runtime";
import { z } from "zod";

import { createAgent, createDefaultAgent } from "./agent/index.js";
import { AgentCoreMemoryClient } from "./memory/client.js";
import { createGatewayMcpClient } from "./mcp/index.js";

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

// Extract gatewayId from ARN: arn:aws:bedrock-agentcore:{region}:{account}:gateway/{gatewayId}
const gatewayId = gatewayArn?.split("/").pop();

if (gatewayId) {
  console.log(`Gateway MCP enabled with Gateway ARN: ${gatewayArn}`);
} else {
  console.log("Gateway MCP disabled (GATEWAY_ARN not set)");
}

// Cache for agent (lazy loaded on first request)
let agentCache: Agent | null = null;

/**
 * Get or create agent with MCP tools (lazy initialization)
 */
async function getAgent(): Promise<Agent> {
  // Return cached agent if available
  if (agentCache) {
    return agentCache;
  }

  // If no gateway configured, use default agent without MCP
  if (!gatewayId) {
    console.log("No Gateway configured, using default agent");
    agentCache = await createDefaultAgent();
    return agentCache;
  }

  try {
    // Create MCP client for Gateway
    const mcpClient = createGatewayMcpClient({
      region,
      gatewayId,
    });

    // Create agent with MCP client
    // The SDK will automatically discover and register tools from the MCP server
    agentCache = await createAgent({ mcpClient });
    console.log("Agent initialized with MCP client for Gateway");

    return agentCache;
  } catch (error) {
    console.warn("Failed to create MCP agent, falling back to default:", error);
    agentCache = await createDefaultAgent();
    return agentCache;
  }
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

      // Get agent (lazy loads MCP tools on first request)
      const agent = await getAgent();

      // Standard agent flow with MCP tools available
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

      // Invoke agent (now has MCP tools registered via McpClient)
      let response: string;
      try {
        const result = await agent.invoke(contextPrompt);
        response = result.toString();
      } catch (invokeError) {
        // Log detailed error information
        console.error("Agent invoke error:", invokeError);
        if (invokeError instanceof Error) {
          console.error("Error name:", invokeError.name);
          console.error("Error message:", invokeError.message);
          console.error("Error stack:", invokeError.stack);
          if ("cause" in invokeError) {
            console.error("Error cause:", invokeError.cause);
          }
        }
        // Re-serialize error properly for response
        const errorMessage =
          invokeError instanceof Error
            ? invokeError.message
            : JSON.stringify(invokeError, null, 2);
        yield {
          event: "error",
          data: { error: errorMessage, sessionId },
        };
        return;
      }

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

console.log("Starting AgentCore Runtime server on port 8080...");
app.run();
