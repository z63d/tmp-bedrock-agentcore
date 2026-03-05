import "dotenv/config";

export interface AgentConfig {
  region: string;
  agentRuntimeArn: string;
}

export function loadConfig(): AgentConfig {
  const agentRuntimeArn = process.env.AGENT_RUNTIME_ARN;

  if (!agentRuntimeArn) {
    console.error("Error: AGENT_RUNTIME_ARN environment variable is required");
    console.error("");
    console.error("Set it in .env file or export it:");
    console.error("  export AGENT_RUNTIME_ARN=arn:aws:bedrock-agentcore:...");
    console.error("");
    console.error("You can get this value from:");
    console.error("  terraform output agent_runtime_arn");
    process.exit(1);
  }

  return {
    region: process.env.AWS_REGION ?? "ap-northeast-1",
    agentRuntimeArn,
  };
}
