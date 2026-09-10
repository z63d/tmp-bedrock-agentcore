import { canvasCreate, type CanvasCreateArgs } from "./canvas-create.js";
import { canvasEdit, type CanvasEditArgs } from "./canvas-edit.js";
import { canvasDelete, type CanvasDeleteArgs } from "./canvas-delete.js";
import { canvasSectionsLookup, type CanvasSectionsLookupArgs } from "./canvas-sections-lookup.js";
import { canvasAccessSet, type CanvasAccessSetArgs } from "./canvas-access-set.js";
import { channelCanvasCreate, type ChannelCanvasCreateArgs } from "./channel-canvas-create.js";

export interface ToolDefinition {
  name: string;
  description: string;
  inputSchema: {
    type: "object";
    properties: Record<string, unknown>;
    required?: string[];
  };
}

export function getToolDefinitions(): ToolDefinition[] {
  return [
    {
      name: "canvas-create",
      description: "Create a new standalone Slack canvas with optional markdown content",
      inputSchema: {
        type: "object",
        properties: {
          title: { type: "string", description: "Canvas title" },
          markdown: { type: "string", description: "Initial content in markdown format" },
          channel_id: { type: "string", description: "Channel ID to tab the canvas in" },
        },
      },
    },
    {
      name: "canvas-edit",
      description: "Edit a Slack canvas (insert, replace, delete content or rename)",
      inputSchema: {
        type: "object",
        properties: {
          canvas_id: { type: "string", description: "Canvas ID (F-prefixed)" },
          operation: {
            type: "string",
            enum: ["insert_at_start", "insert_at_end", "insert_after", "insert_before", "replace", "delete", "rename"],
            description: "Edit operation type",
          },
          markdown: { type: "string", description: "Content in markdown format (for insert/replace operations)" },
          section_id: { type: "string", description: "Target section ID (required for insert_after, insert_before, delete)" },
          title: { type: "string", description: "New title (for rename operation)" },
        },
        required: ["canvas_id", "operation"],
      },
    },
    {
      name: "canvas-delete",
      description: "Permanently delete a Slack canvas (cannot be undone)",
      inputSchema: {
        type: "object",
        properties: {
          canvas_id: { type: "string", description: "Canvas ID to delete" },
        },
        required: ["canvas_id"],
      },
    },
    {
      name: "canvas-sections-lookup",
      description: "Find sections in a canvas by type or text content",
      inputSchema: {
        type: "object",
        properties: {
          canvas_id: { type: "string", description: "Canvas ID" },
          criteria: {
            type: "object",
            description: "Search criteria with optional section_types and contains_text",
          },
        },
        required: ["canvas_id", "criteria"],
      },
    },
    {
      name: "canvas-access-set",
      description: "Set access permissions on a canvas for channels or users",
      inputSchema: {
        type: "object",
        properties: {
          canvas_id: { type: "string", description: "Canvas ID" },
          access_level: {
            type: "string",
            enum: ["read", "write", "owner"],
            description: "Access level to grant",
          },
          channel_ids: {
            type: "array",
            items: { type: "string" },
            description: "Channel IDs to grant access (mutually exclusive with user_ids)",
          },
          user_ids: {
            type: "array",
            items: { type: "string" },
            description: "User IDs to grant access (mutually exclusive with channel_ids)",
          },
        },
        required: ["canvas_id", "access_level"],
      },
    },
    {
      name: "channel-canvas-create",
      description: "Create a channel canvas (resource hub). One per channel maximum.",
      inputSchema: {
        type: "object",
        properties: {
          channel_id: { type: "string", description: "Channel ID" },
          title: { type: "string", description: "Canvas title" },
          markdown: { type: "string", description: "Initial content in markdown format" },
        },
        required: ["channel_id"],
      },
    },
  ];
}

type ToolFunction = (args: Record<string, unknown>) => Promise<unknown>;

const toolMap: Record<string, ToolFunction> = {
  "canvas-create": (args) => canvasCreate(args as unknown as CanvasCreateArgs),
  "canvas-edit": (args) => canvasEdit(args as unknown as CanvasEditArgs),
  "canvas-delete": (args) => canvasDelete(args as unknown as CanvasDeleteArgs),
  "canvas-sections-lookup": (args) => canvasSectionsLookup(args as unknown as CanvasSectionsLookupArgs),
  "canvas-access-set": (args) => canvasAccessSet(args as unknown as CanvasAccessSetArgs),
  "channel-canvas-create": (args) => channelCanvasCreate(args as unknown as ChannelCanvasCreateArgs),
};

export async function executeTool(
  toolName: string,
  args: Record<string, unknown>
): Promise<unknown> {
  const tool = toolMap[toolName];
  if (!tool) throw new Error(`Unknown tool: ${toolName}`);
  return tool(args);
}
