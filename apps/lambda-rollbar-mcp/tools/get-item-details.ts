/**
 * Get Item Details Tool
 * Retrieves detailed information about a Rollbar item by its counter
 */

import { ROLLBAR_API_BASE } from "../config.js";
import { makeRollbarRequest } from "../utils/api.js";
import { truncateOccurrence } from "../utils/truncation.js";
import type {
  RollbarApiResponse,
  RollbarItemResponse,
  RollbarOccurrenceResponse,
} from "../types/index.js";

export interface GetItemDetailsArgs {
  counter: number;
  max_tokens?: number;
}

export async function getItemDetails(
  args: GetItemDetailsArgs,
  accessToken: string
): Promise<unknown> {
  const { counter, max_tokens = 20000 } = args;

  // Get item by counter (API redirects and returns item data)
  const counterUrl = `${ROLLBAR_API_BASE}/item_by_counter/${counter}`;
  const itemResponse = await makeRollbarRequest<
    RollbarApiResponse<RollbarItemResponse>
  >(counterUrl, "get-item-details", accessToken);

  if (itemResponse.err !== 0) {
    const errorMessage =
      itemResponse.message || `Unknown error (code: ${itemResponse.err})`;
    throw new Error(`Rollbar API returned error: ${errorMessage}`);
  }

  const item = itemResponse.result;

  // Get the last occurrence for this item
  const occurrenceUrl = `${ROLLBAR_API_BASE}/instance/${item.last_occurrence_id}`;
  const occurrenceResponse = await makeRollbarRequest<
    RollbarApiResponse<RollbarOccurrenceResponse>
  >(occurrenceUrl, "get-item-details", accessToken);

  if (occurrenceResponse.err !== 0) {
    // We got the item but failed to get occurrence. Return just the item data.
    return item;
  }

  const occurrence = occurrenceResponse.result;

  // Remove the metadata section from occurrence.data
  if (occurrence.data && occurrence.data.metadata) {
    delete occurrence.data.metadata;
  }

  // Combine item and occurrence data
  const responseData = {
    ...item,
    occurrence: truncateOccurrence(occurrence, max_tokens),
  };

  return responseData;
}
