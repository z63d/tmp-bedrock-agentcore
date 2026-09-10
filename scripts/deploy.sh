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
  all                  Build and push all images

Examples:
  $(basename "$0") agent
  $(basename "$0") google-workspace
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

[[ $# -lt 1 ]] && usage

case "$1" in
  agent)
    deploy_agent
    ;;
  google-workspace)
    deploy_google_workspace
    ;;
  all)
    deploy_agent
    deploy_google_workspace
    ;;
  *)
    echo "Unknown target: $1"
    usage
    ;;
esac
