/**
 * Update Item Tool
 * Updates an item in Rollbar (status, level, title, assignment, etc.)
 */

import { ROLLBAR_API_BASE } from "../config.js";
import { makeRollbarRequest } from "../utils/api.js";
import type { RollbarApiResponse } from "../types/index.js";

export interface UpdateItemArgs {
  itemId: number;
  status?: "active" | "resolved" | "muted" | "archived";
  level?: "debug" | "info" | "warning" | "error" | "critical";
  title?: string;
  assignedUserId?: number;
  resolvedInVersion?: string;
  snoozed?: boolean;
  teamId?: number;
}

export async function updateItem(
  args: UpdateItemArgs,
  accessToken: string
): Promise<unknown> {
  const {
    itemId,
    status,
    level,
    title,
    assignedUserId,
    resolvedInVersion,
    snoozed,
    teamId,
  } = args;

  const updateData: Record<string, unknown> = {};

  if (status !== undefined) updateData.status = status;
  if (level !== undefined) updateData.level = level;
  if (title !== undefined) updateData.title = title;
  if (assignedUserId !== undefined) updateData.assigned_user_id = assignedUserId;
  if (resolvedInVersion !== undefined)
    updateData.resolved_in_version = resolvedInVersion;
  if (snoozed !== undefined) updateData.snoozed = snoozed;
  if (teamId !== undefined) updateData.team_id = teamId;

  if (Object.keys(updateData).length === 0) {
    throw new Error("At least one field must be provided to update");
  }

  const url = `${ROLLBAR_API_BASE}/item/${itemId}`;
  const response = await makeRollbarRequest<RollbarApiResponse<unknown>>(
    url,
    "update-item",
    accessToken,
    {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(updateData),
    }
  );

  if (response.err !== 0) {
    const errorMessage =
      response.message || `Unknown error (code: ${response.err})`;
    throw new Error(`Rollbar API returned error: ${errorMessage}`);
  }

  return response.result;
}
