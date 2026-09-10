import { slackRequest } from "../config.js";

export interface CanvasSectionsLookupArgs {
  canvas_id: string;
  criteria: {
    section_types?: string[];
    contains_text?: string;
  };
}

export async function canvasSectionsLookup(args: CanvasSectionsLookupArgs): Promise<unknown> {
  return slackRequest("canvases.sections.lookup", {
    canvas_id: args.canvas_id,
    criteria: args.criteria,
  });
}
