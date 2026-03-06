import {
  BedrockAgentCoreClient,
  InvokeAgentRuntimeCommand,
} from "@aws-sdk/client-bedrock-agentcore";
import { randomUUID } from "crypto";
import type { AgentConfig } from "./config.js";

export class AgentCoreClient {
  private client: BedrockAgentCoreClient;
  private agentRuntimeArn: string;
  private sessionId: string;

  constructor(config: AgentConfig, sessionId?: string) {
    this.client = new BedrockAgentCoreClient({ region: config.region });
    this.agentRuntimeArn = config.agentRuntimeArn;
    // Session ID must be 33+ characters
    this.sessionId = sessionId ?? `cli-${randomUUID()}-${Date.now()}`;
  }

  getSessionId(): string {
    return this.sessionId;
  }

  async invoke(prompt: string): Promise<string> {
    const payload = JSON.stringify({ prompt, sessionId: this.sessionId });

    const command = new InvokeAgentRuntimeCommand({
      agentRuntimeArn: this.agentRuntimeArn,
      runtimeSessionId: this.sessionId,
      payload: new TextEncoder().encode(payload),
      contentType: "application/json",
      accept: "text/event-stream",
    });

    const response = await this.client.send(command);

    if (!response.response) {
      throw new Error("No response from AgentCore");
    }

    const rawText = await response.response.transformToString();

    // Parse SSE (Server-Sent Events) format
    // Format: "event: message\ndata: {...}\n"
    return this.parseSSE(rawText);
  }

  private parseSSE(raw: string): string {
    const lines = raw.split("\n");
    const results: string[] = [];

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      if (line.startsWith("data: ")) {
        const dataStr = line.slice(6); // Remove "data: " prefix
        try {
          const data = JSON.parse(dataStr);
          if (data.text) {
            results.push(data.text);
          }
        } catch {
          // Not JSON, use as-is
          results.push(dataStr);
        }
      }
    }

    return results.join("\n") || raw;
  }
}
