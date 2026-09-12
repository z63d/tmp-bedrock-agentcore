import {
  BedrockAgentCoreClient,
  InvokeAgentRuntimeCommand,
} from "@aws-sdk/client-bedrock-agentcore";
import {
  SecretsManagerClient,
  GetSecretValueCommand,
} from "@aws-sdk/client-secrets-manager";
import { LambdaClient, InvokeCommand } from "@aws-sdk/client-lambda";
import { WebClient } from "@slack/web-api";
import { createHmac, timingSafeEqual } from "crypto";
import type { APIGatewayProxyEventV2, Context } from "aws-lambda";

const region = process.env.AWS_REGION ?? "ap-northeast-1";
const runtimeArn = process.env.AGENT_RUNTIME_ARN!;
const functionName = process.env.AWS_LAMBDA_FUNCTION_NAME!;

const allowedSlackChannels = new Set(
  (process.env.ALLOWED_SLACK_CHANNEL_IDS ?? "").split(",").filter(Boolean)
);
const allowedSlackUsers = new Set(
  (process.env.ALLOWED_SLACK_USER_IDS ?? "").split(",").filter(Boolean)
);

const secretsClient = new SecretsManagerClient({ region });
const agentCoreClient = new BedrockAgentCoreClient({ region });
const lambdaClient = new LambdaClient({ region });

async function getSecret(arn: string): Promise<string> {
  const res = await secretsClient.send(
    new GetSecretValueCommand({ SecretId: arn })
  );
  return res.SecretString!;
}

const [slackBotToken, slackSigningSecret] = await Promise.all([
  getSecret(process.env.SLACK_BOT_TOKEN_SECRET_ARN!),
  getSecret(process.env.SLACK_SIGNING_SECRET_SECRET_ARN!),
]);

const slack = new WebClient(slackBotToken);

// --- Slack signature verification ---

function verifySignature(
  headers: Record<string, string | undefined>,
  body: string
): boolean {
  const timestamp = headers["x-slack-request-timestamp"];
  const signature = headers["x-slack-signature"];
  if (!timestamp || !signature) return false;

  if (Math.abs(Date.now() / 1000 - Number(timestamp)) > 5 * 60) return false;

  const expected =
    "v0=" +
    createHmac("sha256", slackSigningSecret)
      .update(`v0:${timestamp}:${body}`)
      .digest("hex");

  return timingSafeEqual(Buffer.from(expected), Buffer.from(signature));
}

// --- AgentCore ---

async function invokeAgent(text: string, sessionId: string): Promise<string> {
  const payload = JSON.stringify({ prompt: text, sessionId });

  const response = await agentCoreClient.send(
    new InvokeAgentRuntimeCommand({
      agentRuntimeArn: runtimeArn,
      runtimeSessionId: sessionId,
      payload: new TextEncoder().encode(payload),
      contentType: "application/json",
      accept: "text/event-stream",
    })
  );

  if (!response.response) throw new Error("No response from AgentCore");

  // Read SSE stream chunk-by-chunk instead of transformToString() which
  // can hang waiting for the connection to close
  const reader = response.response.transformToWebStream().getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  const results: string[] = [];

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });

    let newlineIdx: number;
    while ((newlineIdx = buffer.indexOf("\n")) !== -1) {
      const line = buffer.slice(0, newlineIdx).trimEnd();
      buffer = buffer.slice(newlineIdx + 1);

      if (line.startsWith("data: ")) {
        try {
          const data = JSON.parse(line.slice(6));
          if (data.text) results.push(data.text);
          if (data.error) results.push(data.error);
        } catch {
          results.push(line.slice(6));
        }
      }
    }
  }

  if (!results.length) throw new Error("No response data from AgentCore");
  return results.join("\n");
}

function truncate(text: string, limit = 3900): string {
  if (text.length <= limit) return text;
  return text.slice(0, limit) + "\n\n... (truncated)";
}

// --- Async payload (2nd invocation) ---

interface AsyncPayload {
  __async: true;
  channel: string;
  threadTs: string;
  messageTs: string;
  text: string;
}

async function processAsync(payload: AsyncPayload): Promise<void> {
  const { channel, threadTs, messageTs, text } = payload;

  const pending = await slack.chat.postMessage({
    channel,
    text: ":loading: Processing...",
    thread_ts: threadTs,
  });

  const startTime = Date.now();
  const timer = setInterval(async () => {
    const sec = Math.floor((Date.now() - startTime) / 1000);
    const label = sec < 60 ? `${sec}s` : `${Math.floor(sec / 60)}m${sec % 60}s`;
    await slack.chat.update({
      channel,
      ts: pending.ts!,
      text: `:loading: Processing... (${label})`,
    }).catch(() => {});
  }, 10_000);
 
  const sessionId = `slack-${channel}-${threadTs.replace(".", "")}`;

  try {
    const result = await invokeAgent(text, sessionId);
    clearInterval(timer);
    await slack.chat.update({
      channel,
      ts: pending.ts!,
      text: truncate(result),
    });
  } catch (error) {
    clearInterval(timer);
    console.error("AgentCore invocation failed:", error);
    const message = error instanceof Error ? error.message : String(error);
    await slack.chat.update({
      channel,
      ts: pending.ts!,
      text: truncate(`:x: Error: ${message}`),
    });
  }
}

// --- Lambda handler ---

export async function handler(
  event: APIGatewayProxyEventV2 | AsyncPayload,
  _context: Context
) {
  // 2nd invocation: async processing
  if ("__async" in event && event.__async) {
    await processAsync(event as AsyncPayload);
    return { statusCode: 200, body: "ok" };
  }

  // 1st invocation: Slack event
  const httpEvent = event as APIGatewayProxyEventV2;

  if (httpEvent.headers?.["x-slack-retry-num"]) {
    return { statusCode: 200, body: "ok" };
  }

  const body = httpEvent.isBase64Encoded
    ? Buffer.from(httpEvent.body ?? "", "base64").toString()
    : httpEvent.body ?? "";

  // Verify signature
  if (!verifySignature(httpEvent.headers, body)) {
    return { statusCode: 401, body: "invalid signature" };
  }

  const parsed = JSON.parse(body);

  // URL verification
  if (parsed.type === "url_verification") {
    return {
      statusCode: 200,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ challenge: parsed.challenge }),
    };
  }
  const slackEvent = parsed.event;

  if (
    parsed.type !== "event_callback" ||
    slackEvent?.type !== "app_mention" ||
    slackEvent?.bot_id
  ) {
    return { statusCode: 200, body: "ok" };
  }

  const channel: string = slackEvent.channel;
  const userId: string = slackEvent.user;

  if (allowedSlackChannels.size > 0 && !allowedSlackChannels.has(channel)) {
    return { statusCode: 200, body: "ok" };
  }
  if (allowedSlackUsers.size > 0 && !allowedSlackUsers.has(userId)) {
    return { statusCode: 200, body: "ok" };
  }

  const messageTs: string = slackEvent.ts;
  const threadTs: string = slackEvent.thread_ts ?? messageTs;
  const text = (slackEvent.text as string)
    .replace(/<@[A-Z0-9]+>/g, "")
    .trim();

  if (!text) {
    await slack.chat.postMessage({
      channel,
      text: "何を調査しますか？",
      thread_ts: threadTs,
    });
    return { statusCode: 200, body: "ok" };
  }

  // Self-invoke async
  await lambdaClient.send(
    new InvokeCommand({
      FunctionName: functionName,
      InvocationType: "Event",
      Payload: JSON.stringify({
        __async: true,
        channel,
        threadTs,
        messageTs,
        text,
      } satisfies AsyncPayload),
    })
  );

  return { statusCode: 200, body: "ok" };
}
