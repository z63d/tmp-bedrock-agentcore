import * as readline from "readline";
import type { AgentCoreClient } from "./client.js";

export async function startRepl(client: AgentCoreClient): Promise<void> {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    prompt: "agent> ",
  });

  console.log("AgentCore REPL started.");
  console.log(`Session: ${client.getSessionId()}`);
  console.log('Type "exit" or "quit" to quit.\n');
  rl.prompt();

  rl.on("line", async (line) => {
    const input = line.trim();

    if (input === "exit" || input === "quit") {
      console.log("Bye!");
      rl.close();
      process.exit(0);
    }

    if (!input) {
      rl.prompt();
      return;
    }

    try {
      console.log(""); // blank line before response
      const response = await client.invoke(input);
      console.log(response);
      console.log(""); // blank line after response
    } catch (error) {
      if (error instanceof Error) {
        console.error(`Error: ${error.message}`);
      } else {
        console.error("Error:", error);
      }
      console.log("");
    }

    rl.prompt();
  });

  rl.on("close", () => {
    process.exit(0);
  });
}
