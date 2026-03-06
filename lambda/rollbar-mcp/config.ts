/**
 * Configuration for Rollbar MCP Lambda
 * Uses SSM Parameter Store for secure token storage
 */

import { SSMClient, GetParameterCommand } from "@aws-sdk/client-ssm";

// Rollbar API base URL
export const ROLLBAR_API_BASE = "https://api.rollbar.com/api/1";

// SSM Parameter name for Rollbar access token
const SSM_PARAMETER_NAME = "/rollbar/mcp/access-token";

// Cache the token to avoid repeated SSM calls
let cachedAccessToken: string | null = null;

/**
 * Get the Rollbar access token from SSM Parameter Store.
 * Token is cached after first retrieval.
 */
export async function getAccessToken(): Promise<string> {
  if (cachedAccessToken) {
    return cachedAccessToken;
  }

  const region = process.env.AWS_REGION || "ap-northeast-1";
  const ssm = new SSMClient({ region });

  try {
    const response = await ssm.send(
      new GetParameterCommand({
        Name: SSM_PARAMETER_NAME,
        WithDecryption: true,
      })
    );

    const token = response.Parameter?.Value;
    if (!token) {
      throw new Error(
        `SSM Parameter ${SSM_PARAMETER_NAME} exists but has no value`
      );
    }

    cachedAccessToken = token;
    return token;
  } catch (error) {
    if (
      error instanceof Error &&
      error.name === "ParameterNotFound"
    ) {
      throw new Error(
        `Rollbar access token not found. Please set SSM Parameter: ${SSM_PARAMETER_NAME}`
      );
    }
    throw error;
  }
}

/**
 * Clear the cached token (useful for testing)
 */
export function clearTokenCache(): void {
  cachedAccessToken = null;
}
