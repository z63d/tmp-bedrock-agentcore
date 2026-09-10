const SLACK_API_BASE = "https://slack.com/api";

function getToken(): string {
  const token = process.env.SLACK_BOT_TOKEN;
  if (!token) {
    throw new Error("SLACK_BOT_TOKEN environment variable is not set");
  }
  return token;
}

export async function slackRequest<T>(
  method: string,
  body: Record<string, unknown>
): Promise<T> {
  const response = await fetch(`${SLACK_API_BASE}/${method}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${getToken()}`,
      "Content-Type": "application/json; charset=utf-8",
    },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    throw new Error(`Slack API HTTP error: ${response.status} ${response.statusText}`);
  }

  const data = (await response.json()) as T & { ok: boolean; error?: string };

  if (!data.ok) {
    throw new Error(`Slack API error: ${data.error || "unknown"}`);
  }

  return data;
}
