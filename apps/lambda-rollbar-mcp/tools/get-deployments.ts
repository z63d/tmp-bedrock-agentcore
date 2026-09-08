/**
 * Get Deployments Tool
 * Retrieves deployment information from Rollbar
 */

import { ROLLBAR_API_BASE } from "../config.js";
import { makeRollbarRequest } from "../utils/api.js";
import type {
  RollbarApiResponse,
  RollbarDeployResponse,
} from "../types/index.js";

export interface GetDeploymentsArgs {
  limit: number;
}

export async function getDeployments(
  args: GetDeploymentsArgs,
  accessToken: string
): Promise<unknown> {
  const { limit } = args;

  const deploysUrl = `${ROLLBAR_API_BASE}/deploys?limit=${limit}`;
  const deploysResponse = await makeRollbarRequest<
    RollbarApiResponse<RollbarDeployResponse>
  >(deploysUrl, "get-deployments", accessToken);

  if (deploysResponse.err !== 0) {
    const errorMessage =
      deploysResponse.message || `Unknown error (code: ${deploysResponse.err})`;
    throw new Error(`Rollbar API returned error: ${errorMessage}`);
  }

  return deploysResponse.result;
}
