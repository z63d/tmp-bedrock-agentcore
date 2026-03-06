# ===============================
# Stage 1: Builder
# ===============================
FROM ghcr.io/astral-sh/uv:python3.13-bookworm-slim AS builder

WORKDIR /app

# Copy dependency files
COPY pyproject.toml ./

# Install dependencies with uv
RUN uv pip install --system --no-cache .

# Copy source code
COPY src/ ./src/

# ===============================
# Stage 2: Runtime
# ===============================
FROM python:3.13-slim-bookworm AS runtime

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /usr/local/lib/python3.13/site-packages /usr/local/lib/python3.13/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Copy application code
COPY --from=builder /app/src ./src

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONPATH=/app/src

# OpenTelemetry configuration
ENV OTEL_PYTHON_DISTRO=aws_distro
ENV OTEL_PYTHON_CONFIGURATOR=aws_configurator
ENV OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
ENV OTEL_TRACES_EXPORTER=otlp
ENV OTEL_RESOURCE_ATTRIBUTES=service.name=bedrock-agentcore-app
ENV OTEL_EXPORTER_OTLP_LOGS_HEADERS="x-aws-log-group=/aws/vendedlogs/bedrock-agentcore/bedrock-agentcore-ts,x-aws-log-stream=default,x-aws-metric-namespace=bedrock-agentcore"
ENV AGENT_OBSERVABILITY_ENABLED=true

EXPOSE 8080

# Run with OpenTelemetry instrumentation
CMD ["opentelemetry-instrument", "python", "-m", "bedrock_agentcore_app.main"]
