/**
 * List Items Tool
 * Lists items in the Rollbar project with optional filtering
 */

import { ROLLBAR_API_BASE } from "../config.js";
import { makeRollbarRequest } from "../utils/api.js";
import type {
  RollbarApiResponse,
  RollbarListItemsResponse,
} from "../types/index.js";

export interface ListItemsArgs {
  status?: string;
  level?: string[];
  environment?: string;
  page?: number;
  limit?: number;
  query?: string;
}

export async function listItems(
  args: ListItemsArgs,
  accessToken: string
): Promise<unknown> {
  const {
    status = "active",
    level,
    environment = "production",
    page = 1,
    limit = 20,
    query,
  } = args;

  // Build query parameters
  const params = new URLSearchParams();

  if (status) {
    params.append("status", status);
  }

  if (level && level.length > 0) {
    level.forEach((l) => params.append("level", l));
  }

  if (environment) {
    params.append("environment", environment);
  }

  if (page && page > 1) {
    params.append("page", page.toString());
  }

  if (limit) {
    params.append("limit", limit.toString());
  }

  if (query) {
    params.append("q", query);
  }

  const listUrl = `${ROLLBAR_API_BASE}/items/?${params.toString()}`;

  const listResponse = await makeRollbarRequest<
    RollbarApiResponse<RollbarListItemsResponse>
  >(listUrl, "list-items", accessToken);

  if (listResponse.err !== 0) {
    const errorMessage =
      listResponse.message || `Unknown error (code: ${listResponse.err})`;
    throw new Error(`Rollbar API returned error: ${errorMessage}`);
  }

  const itemsData = listResponse.result;

  // Format the response to include pagination info and items
  const formattedResponse = {
    items: itemsData.items,
    pagination: {
      page: itemsData.page,
      total_count: itemsData.total_count,
      items_on_page: itemsData.items.length,
    },
    filters_applied: {
      status: status || null,
      level: level || null,
      environment: environment || null,
      query: query || null,
    },
  };

  return formattedResponse;
}
