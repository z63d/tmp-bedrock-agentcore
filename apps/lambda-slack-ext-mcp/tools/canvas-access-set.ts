import { slackRequest } from "../config.js";

export interface CanvasAccessSetArgs {
  canvas_id: string;
  access_level: "read" | "write" | "owner";
  channel_ids?: string | string[];
  user_ids?: string | string[];
}

function toArray(value: string | string[] | undefined): string[] | undefined {
  if (!value) return undefined;
  if (Array.isArray(value)) return value;
  return value.split(",").map((s) => s.trim()).filter(Boolean);
}

export async function canvasAccessSet(args: CanvasAccessSetArgs): Promise<unknown> {
  const body: Record<string, unknown> = {
    canvas_id: args.canvas_id,
    access_level: args.access_level,
  };

  const channelIds = toArray(args.channel_ids);
  const userIds = toArray(args.user_ids);
  if (channelIds) body.channel_ids = channelIds;
  if (userIds) body.user_ids = userIds;

  return slackRequest("canvases.access.set", body);
}
