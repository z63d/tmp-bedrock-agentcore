FROM public.ecr.aws/docker/library/node:22-slim

COPY --from=public.ecr.aws/awsguru/aws-lambda-adapter:1.0.1 /lambda-adapter /opt/extensions/lambda-adapter

RUN npm install -g @piotr-agier/google-drive-mcp

COPY proxy.mjs /app/proxy.mjs

# Lambda Web Adapter
ENV AWS_LWA_PORT=8080
ENV AWS_LWA_READINESS_CHECK_PORT=8080
ENV AWS_LWA_READINESS_CHECK_PATH=/
ENV AWS_LWA_READINESS_CHECK_MIN_UNHEALTHY_STATUS=500
ENV AWS_LWA_INVOKE_MODE=response_stream
ENV AWS_LWA_INIT_BINARY_PATH=/opt/extensions/lambda-adapter
ENV AWS_LWA_STARTUP_TIMEOUT_MS=10000

# google-drive-mcp
ENV GOOGLE_DRIVE_MCP_SCOPES="drive,documents"
ENV HOME=/tmp

# SA key JSON is passed via GOOGLE_CLOUD_SA_KEY_JSON env var.
# Written to /tmp/sa-key.json at startup so GOOGLE_APPLICATION_CREDENTIALS can reference it.
#
# TODO: Migrate to Workload Identity Federation (no key file needed)
# See wif-credential-config.json.example for the WIF approach.

# proxy.mjs intercepts server/discover (MCP 2026-07-28) which SDK 1.x doesn't support,
# then forwards all other requests to the actual MCP server on port 8081.
CMD ["sh", "-c", "printf '%s' \"$GOOGLE_CLOUD_SA_KEY_JSON\" > /tmp/sa-key.json && GOOGLE_APPLICATION_CREDENTIALS=/tmp/sa-key.json npx @piotr-agier/google-drive-mcp --transport http --host 0.0.0.0 --port 8081 & node /app/proxy.mjs"]
