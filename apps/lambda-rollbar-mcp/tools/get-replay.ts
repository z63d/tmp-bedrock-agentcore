/**
 * Get Replay Tool
 * Retrieves session replay data from Rollbar
 * Modified for Lambda: Returns JSON directly (no file/resource modes)
 */

import { ROLLBAR_API_BASE } from "../config.js";
import { makeRollbarRequest } from "../utils/api.js";
import type { RollbarApiResponse } from "../types/index.js";

export interface GetReplayArgs {
  environment: string;
  sessionId: string;
  replayId: string;
}

function buildReplayApiUrl(
  environment: string,
  sessionId: string,
  replayId: string
): string {
  return `${ROLLBAR_API_BASE}/environment/${encodeURIComponent(
    environment
  )}/session/${encodeURIComponent(sessionId)}/replay/${encodeURIComponent(
    replayId
  )}`;
}

export async function getReplay(
  args: GetReplayArgs,
  accessToken: string
): Promise<unknown> {
  const { environment, sessionId, replayId } = args;

  const replayUrl = buildReplayApiUrl(environment, sessionId, replayId);

  const replayResponse = await makeRollbarRequest<RollbarApiResponse<unknown>>(
    replayUrl,
    "get-replay",
    accessToken
  );

  if (replayResponse.err !== 0) {
    const errorMessage =
      replayResponse.message || `Unknown error (code: ${replayResponse.err})`;
    throw new Error(`Rollbar API returned error: ${errorMessage}`);
  }

  // Return replay data directly as JSON
  return {
    environment,
    sessionId,
    replayId,
    data: replayResponse.result,
  };
}
