import { slackRequest } from "../config.js";

export interface CanvasDeleteArgs {
  canvas_id: string;
}

export async function canvasDelete(args: CanvasDeleteArgs): Promise<unknown> {
  return slackRequest("canvases.delete", { canvas_id: args.canvas_id });
}
