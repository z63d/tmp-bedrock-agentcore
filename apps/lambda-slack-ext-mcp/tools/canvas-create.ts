import { slackRequest } from "../config.js";

export interface CanvasCreateArgs {
  title?: string;
  markdown?: string;
  channel_id?: string;
}

export async function canvasCreate(args: CanvasCreateArgs): Promise<unknown> {
  const body: Record<string, unknown> = {};
  if (args.title) body.title = args.title;
  if (args.channel_id) body.channel_id = args.channel_id;
  if (args.markdown) {
    body.document_content = { type: "markdown", markdown: args.markdown };
  }

  return slackRequest("canvases.create", body);
}
