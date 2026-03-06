#!/usr/bin/env node
import { parseArgs } from "util";
import { loadConfig } from "./config.js";
import { AgentCoreClient } from "./client.js";
import { startRepl } from "./repl.js";

async function main() {
  const { values, positionals } = parseArgs({
    options: {
      interactive: { type: "boolean", short: "i" },
      help: { type: "boolean", short: "h" },
      session: { type: "string", short: "s" },
    },
    allowPositionals: true,
  });

  if (values.help) {
    console.log(`
AgentCore CLI - Invoke AgentCore Runtime from the command line

Usage:
  npm run cli -- [options] [prompt]

Options:
  -i, --interactive      Start interactive REPL mode
  -s, --session <id>     Use existing session ID (resume conversation)
  -h, --help             Show this help message

Examples:
  npm run cli -- "What is machine learning?"
  npm run cli -- -s "cli-abc123-1234567890"
  npm run cli

Environment Variables:
  AGENT_RUNTIME_ARN  (required) AgentCore Runtime ARN
  AWS_REGION         (optional) AWS region (default: ap-northeast-1)
`);
    process.exit(0);
  }

  const config = loadConfig();
  const client = new AgentCoreClient(config, values.session);

  // If no arguments or -i flag, start REPL
  if (values.interactive || positionals.length === 0) {
    await startRepl(client);
  } else {
    // Single invocation mode
    const prompt = positionals.join(" ");
    try {
      const response = await client.invoke(prompt);
      console.log(response);
    } catch (error) {
      if (error instanceof Error) {
        console.error(`Error: ${error.message}`);
      } else {
        console.error("Error:", error);
      }
      process.exit(1);
    }
  }
}

main().catch((error) => {
  console.error("Fatal error:", error);
  process.exit(1);
});
