/**
 * Get Top Items Tool
 * Retrieves the top active items in the Rollbar project
 */

import { ROLLBAR_API_BASE } from "../config.js";
import { makeRollbarRequest } from "../utils/api.js";
import type {
  RollbarApiResponse,
  RollbarTopItemResponse,
} from "../types/index.js";

export interface GetTopItemsArgs {
  environment?: string;
}

export async function getTopItems(
  args: GetTopItemsArgs,
  accessToken: string
): Promise<unknown> {
  const { environment = "production" } = args;

  const reportUrl = `${ROLLBAR_API_BASE}/reports/top_active_items?hours=24&environments=${encodeURIComponent(environment)}&sort=occurrences`;
  const reportResponse = await makeRollbarRequest<
    RollbarApiResponse<RollbarTopItemResponse>
  >(reportUrl, "get-top-items", accessToken);

  if (reportResponse.err !== 0) {
    const errorMessage =
      reportResponse.message || `Unknown error (code: ${reportResponse.err})`;
    throw new Error(`Rollbar API returned error: ${errorMessage}`);
  }

  return reportResponse.result;
}
