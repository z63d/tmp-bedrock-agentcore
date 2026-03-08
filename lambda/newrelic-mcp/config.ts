/**
 * Configuration for New Relic MCP Lambda
 * Uses AgentCore Identity for secure API key storage
 */

import {
  BedrockAgentCoreClient,
  GetResourceApiKeyCommand,
  GetWorkloadAccessTokenForUserIdCommand,
} from "@aws-sdk/client-bedrock-agentcore";

// New Relic MCP endpoints
const NEWRELIC_MCP_ENDPOINTS = {
  us: "https://mcp.newrelic.com/mcp/",
  eu: "https://mcp.eu.newrelic.com/mcp/",
} as const;

export type NewRelicRegion = keyof typeof NEWRELIC_MCP_ENDPOINTS;

// Environment variable names
const WORKLOAD_IDENTITY_NAME = process.env.WORKLOAD_IDENTITY_NAME;
const API_KEY_CREDENTIAL_PROVIDER_NAME = process.env.API_KEY_CREDENTIAL_PROVIDER_NAME;
const NEWRELIC_MCP_REGION = (process.env.NEWRELIC_MCP_REGION || "us") as NewRelicRegion;

// Cache the API key to avoid repeated API calls
let cachedApiKey: string | null = null;

/**
 * Get the New Relic MCP endpoint URL based on region
 */
export function getMcpEndpoint(): string {
  return NEWRELIC_MCP_ENDPOINTS[NEWRELIC_MCP_REGION];
}

/**
 * Get the New Relic API key from AgentCore Identity.
 * API key is cached after first retrieval.
 */
export async function getApiKey(): Promise<string> {
  if (cachedApiKey) {
    return cachedApiKey;
  }

  if (!WORKLOAD_IDENTITY_NAME) {
    throw new Error("WORKLOAD_IDENTITY_NAME environment variable is not set");
  }

  if (!API_KEY_CREDENTIAL_PROVIDER_NAME) {
    throw new Error("API_KEY_CREDENTIAL_PROVIDER_NAME environment variable is not set");
  }

  const region = process.env.AWS_REGION || "ap-northeast-1";
  const client = new BedrockAgentCoreClient({ region });

  try {
    // Step 1: Get workload access token
    // Using a system user ID since this is M2M authentication
    const workloadTokenResponse = await client.send(
      new GetWorkloadAccessTokenForUserIdCommand({
        workloadName: WORKLOAD_IDENTITY_NAME,
        userId: "system",
      })
    );

    const workloadAccessToken = workloadTokenResponse.workloadAccessToken;
    if (!workloadAccessToken) {
      throw new Error("Failed to get workload access token");
    }

    // Step 2: Get API key using the workload access token
    const apiKeyResponse = await client.send(
      new GetResourceApiKeyCommand({
        workloadIdentityToken: workloadAccessToken,
        resourceCredentialProviderName: API_KEY_CREDENTIAL_PROVIDER_NAME,
      })
    );

    const apiKey = apiKeyResponse.apiKey;
    if (!apiKey) {
      throw new Error("Failed to get API key from AgentCore Identity");
    }

    cachedApiKey = apiKey;
    return apiKey;
  } catch (error) {
    console.error("Error getting API key from AgentCore Identity:", error);
    throw error;
  }
}

/**
 * Clear the cached API key (useful for testing)
 */
export function clearApiKeyCache(): void {
  cachedApiKey = null;
}
