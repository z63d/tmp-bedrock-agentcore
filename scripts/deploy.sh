#!/bin/bash
set -euo pipefail

AWS_REGION="ap-northeast-1"
AWS_PROFILE="pn-playground-admin"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TERRAFORM_DIR="$REPO_ROOT/terraform"
DOCKER_CONFIG="$REPO_ROOT/.docker-tmp"

usage() {
  cat <<EOF
Usage: $(basename "$0") <target>

Targets:
  agent                Build and push AgentCore Runtime image
  google-workspace     Build and push Google Workspace MCP Lambda image
  slack-mcp            Build Slack MCP Go binary (then terraform apply)
  slack-bot            Build Slack Bot + Slack Ext MCP (then terraform apply)
  all                  Build and push all

Examples:
  $(basename "$0") agent
  $(basename "$0") slack-bot
  $(basename "$0") all
EOF
  exit 1
}

ecr_login() {
  local ecr_url="$1"
  DOCKER_HOST=$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true)
  export DOCKER_HOST
  mkdir -p "$DOCKER_CONFIG"
  export DOCKER_CONFIG
  aws ecr get-login-password --region "$AWS_REGION" --profile "$AWS_PROFILE" | \
    docker login --username AWS --password-stdin "$ecr_url"
}

build_and_push() {
  local name="$1"
  local context_dir="$2"
  local ecr_url="$3"

  echo "=== Building $name ==="
  docker build --platform linux/arm64 -t "$name" "$context_dir"

  echo "=== Pushing $name ==="
  ecr_login "$ecr_url"
  docker tag "$name:latest" "$ecr_url:latest"
  docker push "$ecr_url:latest"
  rm -rf "$DOCKER_CONFIG"

  echo "Deployed: $ecr_url:latest"
  echo ""
}

update_lambda_image() {
  local function_name="$1"
  local ecr_url="$2"

  echo "=== Updating Lambda function: $function_name ==="
  aws lambda update-function-code \
    --function-name "$function_name" \
    --image-uri "$ecr_url:latest" \
    --region "$AWS_REGION" --profile "$AWS_PROFILE" \
    --no-cli-pager
  aws lambda wait function-updated \
    --function-name "$function_name" \
    --region "$AWS_REGION" --profile "$AWS_PROFILE"
  echo "Lambda updated: $function_name"
  echo ""
}

deploy_agent() {
  local ecr_url
  ecr_url=$(cd "$TERRAFORM_DIR" && terraform output -raw ecr_repository_url)
  build_and_push "bedrock-agent" "$REPO_ROOT/apps/bedrock-agentcore-sre" "$ecr_url"
}

deploy_google_workspace() {
  local ecr_url
  ecr_url=$(cd "$TERRAFORM_DIR" && terraform output -raw google_workspace_mcp_ecr_url)
  build_and_push "google-workspace-mcp" "$REPO_ROOT/apps/lambda-google-workspace-mcp" "$ecr_url"
  update_lambda_image "k-bedrock-agentcore-google-workspace-mcp" "$ecr_url"
}

deploy_slack_mcp() {
  local app_dir="$REPO_ROOT/apps/lambda-slack-mcp"
  local build_dir="$app_dir/.build"

  echo "=== Building Slack MCP (Go cross-compile) ==="
  rm -rf "$build_dir"
  mkdir -p "$build_dir"

  git clone --depth 1 https://github.com/korotovsky/slack-mcp-server.git "$build_dir/src"
  cd "$build_dir/src"
  CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o "$app_dir/mcp-server" ./cmd/slack-mcp-server
  cd "$REPO_ROOT"

  chmod +x "$app_dir/mcp-server"
  rm -rf "$build_dir"

  echo "Built: $app_dir/mcp-server"
  echo "Run 'cd terraform && terraform apply' to deploy."
  echo ""
}

deploy_slack_bot() {
  echo "=== Building lambda-slack-bot ==="
  cd "$REPO_ROOT/apps/lambda-slack-bot"
  npm install
  npm run build

  echo "=== Building lambda-slack-ext-mcp ==="
  cd "$REPO_ROOT/apps/lambda-slack-ext-mcp"
  npm install
  npm run build

  cd "$REPO_ROOT"
  echo "Build complete. Run 'cd terraform && terraform apply' to deploy."
  echo ""
}

[[ $# -lt 1 ]] && usage

case "$1" in
  agent)
    deploy_agent
    ;;
  google-workspace)
    deploy_google_workspace
    ;;
  slack-mcp)
    deploy_slack_mcp
    ;;
  slack-bot)
    deploy_slack_bot
    ;;
  all)
    deploy_agent
    deploy_google_workspace
    deploy_slack_mcp
    deploy_slack_bot
    ;;
  *)
    echo "Unknown target: $1"
    usage
    ;;
esac
