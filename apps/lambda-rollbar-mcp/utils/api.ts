/**
 * Rollbar API Request Helper
 * Modified from rollbar-mcp-server to accept accessToken as parameter
 */

const ROLLBAR_MCP_VERSION = "1.0.0";

export function getUserAgent(toolName: string): string {
  return `rollbar-mcp-lambda/${ROLLBAR_MCP_VERSION} (tool: ${toolName})`;
}

/**
 * Make a request to the Rollbar API
 * @param url - The API endpoint URL
 * @param toolName - Name of the tool making the request (for User-Agent)
 * @param accessToken - Rollbar access token
 * @param options - Additional fetch options
 */
export async function makeRollbarRequest<T>(
  url: string,
  toolName: string,
  accessToken: string,
  options?: RequestInit
): Promise<T> {
  if (!accessToken) {
    throw new Error("Rollbar access token is required");
  }

  const headers: Record<string, string> = {
    "User-Agent": getUserAgent(toolName),
    "X-Rollbar-Access-Token": accessToken,
    Accept: "application/json",
    ...(options?.headers as Record<string, string>),
  };

  const response = await fetch(url, {
    ...options,
    headers,
  });

  if (!response.ok) {
    const errorText = await response.text();
    let errorMessage = `Rollbar API error: ${response.status} ${response.statusText}`;

    // Try to parse error message from response
    try {
      const errorJson = JSON.parse(errorText) as { message?: string };
      if (errorJson.message) {
        errorMessage = `Rollbar API error: ${errorJson.message}`;
      }
    } catch {
      // If not JSON, include the raw text if it's short
      if (errorText && errorText.length < 200) {
        errorMessage += ` - ${errorText}`;
      }
    }

    throw new Error(errorMessage);
  }

  return (await response.json()) as T;
}
