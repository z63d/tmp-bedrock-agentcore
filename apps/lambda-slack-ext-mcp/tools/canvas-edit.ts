import { slackRequest } from "../config.js";

export interface CanvasEditArgs {
  canvas_id: string;
  operation: "insert_at_start" | "insert_at_end" | "insert_after" | "insert_before" | "replace" | "delete" | "rename";
  markdown?: string;
  section_id?: string;
  title?: string;
}

export async function canvasEdit(args: CanvasEditArgs): Promise<unknown> {
  const change: Record<string, unknown> = { operation: args.operation };

  if (args.operation === "rename") {
    if (!args.title) throw new Error("title is required for rename operation");
    change.title_content = args.title;
  } else if (args.operation === "delete") {
    if (!args.section_id) throw new Error("section_id is required for delete operation");
    change.section_id = args.section_id;
  } else {
    if (["insert_after", "insert_before"].includes(args.operation) && !args.section_id) {
      throw new Error(`section_id is required for ${args.operation} operation`);
    }
    if (["insert_at_start", "insert_at_end", "insert_after", "insert_before", "replace"].includes(args.operation) && !args.markdown) {
      throw new Error(`markdown is required for ${args.operation} operation`);
    }
    change.document_content = { type: "markdown", markdown: args.markdown };
    if (args.section_id) {
      change.section_id = args.section_id;
    }
  }

  return slackRequest("canvases.edit", {
    canvas_id: args.canvas_id,
    changes: [change],
  });
}
