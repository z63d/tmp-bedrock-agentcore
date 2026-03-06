/**
 * Get Version Tool
 * Retrieves version information from Rollbar
 */

import { ROLLBAR_API_BASE } from "../config.js";
import { makeRollbarRequest } from "../utils/api.js";
import type {
  RollbarApiResponse,
  RollbarVersionsResponse,
} from "../types/index.js";

export interface GetVersionArgs {
  version: string;
  environment?: string;
}

export async function getVersion(
  args: GetVersionArgs,
  accessToken: string
): Promise<unknown> {
  const { version, environment = "production" } = args;

  const versionsUrl = `${ROLLBAR_API_BASE}/versions/${encodeURIComponent(version)}?environment=${encodeURIComponent(environment)}`;
  const versionsResponse = await makeRollbarRequest<
    RollbarApiResponse<RollbarVersionsResponse>
  >(versionsUrl, "get-version", accessToken);

  if (versionsResponse.err !== 0) {
    const errorMessage =
      versionsResponse.message ||
      `Unknown error (code: ${versionsResponse.err})`;
    throw new Error(`Rollbar API returned error: ${errorMessage}`);
  }

  return versionsResponse.result;
}
