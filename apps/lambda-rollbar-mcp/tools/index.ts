/**
 * Tools Index
 * Provides tool definitions and execution dispatcher
 */

import { getItemDetails, type GetItemDetailsArgs } from "./get-item-details.js";
import { getDeployments, type GetDeploymentsArgs } from "./get-deployments.js";
import { getVersion, type GetVersionArgs } from "./get-version.js";
import { getTopItems, type GetTopItemsArgs } from "./get-top-items.js";
import { listItems, type ListItemsArgs } from "./list-items.js";
import { updateItem, type UpdateItemArgs } from "./update-item.js";
import { getReplay, type GetReplayArgs } from "./get-replay.js";

/**
 * Tool definition for MCP protocol
 */
export interface ToolDefinition {
  name: string;
  description: string;
  inputSchema: {
    type: "object";
    properties: Record<string, unknown>;
    required?: string[];
  };
}

/**
 * Get all tool definitions for the MCP tools/list response
 */
export function getToolDefinitions(): ToolDefinition[] {
  return [
    {
      name: "get-item-details",
      description:
        "Get detailed information about a Rollbar item by its counter, including the last occurrence data",
      inputSchema: {
        type: "object",
        properties: {
          counter: {
            type: "integer",
            description: "Rollbar item counter",
          },
          max_tokens: {
            type: "integer",
            description:
              "Maximum tokens for occurrence data in response (default: 20000). Occurrence response will be truncated if it exceeds this limit.",
          },
        },
        required: ["counter"],
      },
    },
    {
      name: "get-deployments",
      description: "Get deployment status and information for a Rollbar project",
      inputSchema: {
        type: "object",
        properties: {
          limit: {
            type: "integer",
            description: "Number of deployments to retrieve",
          },
        },
        required: ["limit"],
      },
    },
    {
      name: "get-version",
      description: "Get version data and information for a Rollbar project",
      inputSchema: {
        type: "object",
        properties: {
          version: {
            type: "string",
            description: "Version string (e.g. git sha)",
          },
          environment: {
            type: "string",
            description: "Environment name (default: production)",
          },
        },
        required: ["version"],
      },
    },
    {
      name: "get-top-items",
      description:
        "Get list of top active items in the Rollbar project for the last 24 hours",
      inputSchema: {
        type: "object",
        properties: {
          environment: {
            type: "string",
            description: "Environment name (default: production)",
          },
        },
      },
    },
    {
      name: "list-items",
      description:
        "List all items in the Rollbar project with optional search and filtering",
      inputSchema: {
        type: "object",
        properties: {
          status: {
            type: "string",
            description:
              "Filter by item status: active, resolved, muted, archived (default: active)",
          },
          level: {
            type: "array",
            items: { type: "string" },
            description:
              "Filter by severity levels (e.g., ['error', 'critical', 'warning'])",
          },
          environment: {
            type: "string",
            description: "Filter by environment (default: production)",
          },
          page: {
            type: "integer",
            description: "Page number for pagination (default: 1)",
          },
          limit: {
            type: "integer",
            description: "Number of items per page (default: 20, max: 5000)",
          },
          query: {
            type: "string",
            description: "Search query to filter items by title or content",
          },
        },
      },
    },
    {
      name: "update-item",
      description:
        "Update an item in Rollbar (status, level, title, assignment, etc.)",
      inputSchema: {
        type: "object",
        properties: {
          itemId: {
            type: "integer",
            description: "The ID of the item to update",
          },
          status: {
            type: "string",
            enum: ["active", "resolved", "muted", "archived"],
            description: "The new status for the item",
          },
          level: {
            type: "string",
            enum: ["debug", "info", "warning", "error", "critical"],
            description: "The new level for the item",
          },
          title: {
            type: "string",
            description: "The new title for the item",
          },
          assignedUserId: {
            type: "integer",
            description: "The ID of the user to assign the item to",
          },
          resolvedInVersion: {
            type: "string",
            description: "The version in which the item was resolved",
          },
          snoozed: {
            type: "boolean",
            description: "Whether the item should be snoozed (paid accounts only)",
          },
          teamId: {
            type: "integer",
            description:
              "The ID of the team to assign as owner (Advanced/Enterprise accounts only)",
          },
        },
        required: ["itemId"],
      },
    },
    {
      name: "get-replay",
      description:
        "Get session replay data for a specific replay in Rollbar",
      inputSchema: {
        type: "object",
        properties: {
          environment: {
            type: "string",
            description: "Environment name (e.g., production)",
          },
          sessionId: {
            type: "string",
            description: "Session identifier that owns the replay",
          },
          replayId: {
            type: "string",
            description: "Replay identifier to retrieve",
          },
        },
        required: ["environment", "sessionId", "replayId"],
      },
    },
  ];
}

/**
 * Tool function type
 */
type ToolFunction = (
  args: Record<string, unknown>,
  accessToken: string
) => Promise<unknown>;

/**
 * Map of tool names to their implementation functions
 */
const toolMap: Record<string, ToolFunction> = {
  "get-item-details": (args, token) =>
    getItemDetails(args as unknown as GetItemDetailsArgs, token),
  "get-deployments": (args, token) =>
    getDeployments(args as unknown as GetDeploymentsArgs, token),
  "get-version": (args, token) =>
    getVersion(args as unknown as GetVersionArgs, token),
  "get-top-items": (args, token) =>
    getTopItems(args as unknown as GetTopItemsArgs, token),
  "list-items": (args, token) =>
    listItems(args as unknown as ListItemsArgs, token),
  "update-item": (args, token) =>
    updateItem(args as unknown as UpdateItemArgs, token),
  "get-replay": (args, token) =>
    getReplay(args as unknown as GetReplayArgs, token),
};

/**
 * Execute a tool by name with the given arguments
 */
export async function executeTool(
  toolName: string,
  args: Record<string, unknown>,
  accessToken: string
): Promise<unknown> {
  const tool = toolMap[toolName];

  if (!tool) {
    throw new Error(`Unknown tool: ${toolName}`);
  }

  return tool(args, accessToken);
}
