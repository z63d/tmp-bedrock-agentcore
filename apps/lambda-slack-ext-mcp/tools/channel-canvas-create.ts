import { slackRequest } from "../config.js";

export interface ChannelCanvasCreateArgs {
  channel_id: string;
  title?: string;
  markdown?: string;
}

export async function channelCanvasCreate(args: ChannelCanvasCreateArgs): Promise<unknown> {
  const body: Record<string, unknown> = { channel_id: args.channel_id };
  if (args.title) body.title = args.title;
  if (args.markdown) {
    body.document_content = { type: "markdown", markdown: args.markdown };
  }

  return slackRequest("conversations.canvases.create", body);
}
