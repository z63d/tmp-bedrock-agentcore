/**
 * MCP Client Module
 *
 * Exports MCP client utilities for AgentCore Gateway integration.
 */

export { createGatewayMcpClient, getMcpToolsFromClient } from "./client.js";
export type { GatewayMcpClientConfig } from "./client.js";
export { createSigV4Fetch } from "./sigv4-fetch.js";
export type { SigV4FetchConfig } from "./sigv4-fetch.js";
