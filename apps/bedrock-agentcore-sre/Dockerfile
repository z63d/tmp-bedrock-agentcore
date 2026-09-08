# ===============================
# Stage 1: Builder
# ===============================
FROM ghcr.io/astral-sh/uv:python3.13-bookworm-slim AS builder

WORKDIR /app

# Copy dependency files
COPY pyproject.toml ./

# Install dependencies with uv
RUN uv pip install --system --no-cache .

# Copy source code and skills
COPY src/ ./src/
COPY skills/ ./skills/

# ===============================
# Stage 2: Runtime
# ===============================
FROM python:3.13-slim-bookworm AS runtime

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /usr/local/lib/python3.13/site-packages /usr/local/lib/python3.13/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Copy application code and skills
COPY --from=builder /app/src ./src
COPY --from=builder /app/skills ./skills

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONPATH=/app/src

ENV AGENT_OBSERVABILITY_ENABLED=true

RUN useradd -r -s /bin/false appuser
USER appuser

EXPOSE 8080

CMD ["opentelemetry-instrument", "python", "-m", "bedrock_agentcore_app.main"]
