import {
  BedrockAgentCoreClient,
  CreateEventCommand,
  ListEventsCommand,
  RetrieveMemoryRecordsCommand,
} from "@aws-sdk/client-bedrock-agentcore";

export type MessageRole = "USER" | "ASSISTANT" | "TOOL" | "OTHER";

export interface ConversationTurn {
  role: MessageRole;
  content: string;
}

export interface MemoryClientConfig {
  region: string;
  memoryId: string;
}

export class AgentCoreMemoryClient {
  private client: BedrockAgentCoreClient;
  private memoryId: string;

  constructor(config: MemoryClientConfig) {
    this.client = new BedrockAgentCoreClient({ region: config.region });
    this.memoryId = config.memoryId;
  }

  async createEvent(
    actorId: string,
    sessionId: string,
    turns: ConversationTurn[]
  ): Promise<void> {
    const command = new CreateEventCommand({
      memoryId: this.memoryId,
      actorId,
      sessionId,
      eventTimestamp: new Date(),
      payload: turns.map((turn) => ({
        conversational: {
          role: turn.role,
          content: { text: turn.content },
        },
      })),
    });

    await this.client.send(command);
  }

  async getRecentEvents(
    actorId: string,
    sessionId: string,
    maxResults: number = 10
  ) {
    const command = new ListEventsCommand({
      memoryId: this.memoryId,
      actorId,
      sessionId,
      includePayloads: true,
      maxResults,
    });

    const response = await this.client.send(command);
    return response.events ?? [];
  }

  async searchMemories(query: string, namespace: string = "/", topK: number = 5) {
    const command = new RetrieveMemoryRecordsCommand({
      memoryId: this.memoryId,
      namespace,
      searchCriteria: {
        searchQuery: query,
        topK,
      },
    });

    const response = await this.client.send(command);
    return response.memoryRecordSummaries ?? [];
  }
}
