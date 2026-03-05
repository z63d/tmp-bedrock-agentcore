import { BedrockAgentCoreApp } from "bedrock-agentcore/runtime";
import { z } from "zod";
import { agent } from "./agent/index.js";
import { AgentCoreMemoryClient } from "./memory/client.js";

const region = process.env.AWS_REGION ?? "ap-northeast-1";
const memoryId = process.env.MEMORY_ID;

const memoryClient = memoryId
  ? new AgentCoreMemoryClient({ region, memoryId })
  : null;

if (memoryClient) {
  console.log(`Memory enabled with ID: ${memoryId}`);
} else {
  console.log("Memory disabled (MEMORY_ID not set)");
}

// Request schema - sessionId required for AgentCore (header not passed to container)
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

      // Invoke agent
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

console.log("Starting AgentCore Runtime server on port 8080...");
app.run();
