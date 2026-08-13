/**
 * Configuration for Rollbar MCP Lambda
 * Uses AgentCore Identity for secure token storage
 */

import {
  BedrockAgentCoreClient,
  GetResourceApiKeyCommand,
  GetWorkloadAccessTokenForUserIdCommand,
} from "@aws-sdk/client-bedrock-agentcore";

// Rollbar API base URL
export const ROLLBAR_API_BASE = "https://api.rollbar.com/api/1";

// Environment variable names
const WORKLOAD_IDENTITY_NAME = process.env.WORKLOAD_IDENTITY_NAME;
const API_KEY_CREDENTIAL_PROVIDER_NAME = process.env.API_KEY_CREDENTIAL_PROVIDER_NAME;

// Cache the token to avoid repeated API calls
let cachedAccessToken: string | null = null;

/**
 * Get the Rollbar access token from AgentCore Identity.
 * Token is cached after first retrieval.
 */
export async function getAccessToken(): Promise<string> {
  if (cachedAccessToken) {
    return cachedAccessToken;
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

    cachedAccessToken = apiKey;
    return apiKey;
  } catch (error) {
    console.error("Error getting access token from AgentCore Identity:", error);
    throw error;
  }
}

/**
 * Clear the cached token (useful for testing)
 */
export function clearTokenCache(): void {
  cachedAccessToken = null;
}
