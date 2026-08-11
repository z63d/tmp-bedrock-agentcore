/**
 * MCP Client Factory for AgentCore Gateway
 *
 * Creates McpClient instances configured with AWS SigV4 authentication
 * for connecting to AgentCore Gateway MCP endpoints.
 */

import { McpClient } from "@strands-agents/sdk";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";
import type { Transport } from "@modelcontextprotocol/sdk/shared/transport.js";
import { createSigV4Fetch } from "./sigv4-fetch.js";

export interface GatewayMcpClientConfig {
  /** AWS region */
  region: string;
  /** Gateway ID (from ARN) */
  gatewayId: string;
  /** Application name for MCP client identification */
  applicationName?: string;
  /** Application version */
  applicationVersion?: string;
}

/**
 * Create an MCP client for AgentCore Gateway
 *
 * @param config Gateway configuration
 * @returns Configured McpClient instance
 */
export function createGatewayMcpClient(config: GatewayMcpClientConfig): McpClient {
  const {
    region,
    gatewayId,
    applicationName = "bedrock-agentcore-app",
    applicationVersion = "1.0.0",
  } = config;

  // Build Gateway MCP endpoint URL
  const gatewayUrl = new URL(
    `https://${gatewayId}.gateway.bedrock-agentcore.${region}.amazonaws.com/mcp`
  );

  // Create SigV4 signed fetch function
  const sigV4Fetch = createSigV4Fetch({ region });

  // Create transport with SigV4 authentication
  const transport = new StreamableHTTPClientTransport(gatewayUrl, {
    fetch: sigV4Fetch,
  });

  // Create and return McpClient
  return new McpClient({
    transport: transport as Transport,
    applicationName,
    applicationVersion,
  });
}

/**
 * Get MCP tools from Gateway as an array that can be passed to Agent
 *
 * @param client McpClient instance
 * @returns Array of MCP tool instances
 */
export async function getMcpToolsFromClient(client: McpClient): Promise<unknown[]> {
  try {
    const tools = await client.listTools();
    console.log(`Loaded ${tools.length} MCP tools:`, tools.map(t => t.name));
    return tools;
  } catch (error) {
    console.warn("Failed to list MCP tools:", error);
    return [];
  }
}
