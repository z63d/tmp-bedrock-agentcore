#!/bin/bash
set -e

AWS_REGION="ap-northeast-1"
AWS_PROFILE="pn-playground-admin"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCKER_CONFIG="$REPO_ROOT/.docker-tmp"

# Get ECR URL from Terraform
cd "$(dirname "$0")/../terraform"
ECR_REPO=$(terraform output -raw ecr_repository_url)

cd ../app-py

# Docker build
echo "Building Docker image..."
docker build -t bedrock-agent .

# ECR login (isolated config to avoid credHelpers interference)
echo "Logging in to ECR..."
DOCKER_HOST=$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null || true)
export DOCKER_HOST
mkdir -p "$DOCKER_CONFIG"
export DOCKER_CONFIG
aws ecr get-login-password --region "$AWS_REGION" --profile "$AWS_PROFILE" | \
  docker login --username AWS --password-stdin "$ECR_REPO"

# Tag and push
echo "Pushing to ECR..."
docker tag bedrock-agent:latest "$ECR_REPO:latest"
docker push "$ECR_REPO:latest"
rm -rf "$DOCKER_CONFIG"

echo ""
echo "Deployed to: $ECR_REPO:latest"
echo ""
echo "To invoke the agent:"
echo "  RUNTIME_ARN=\$(cd ../terraform && terraform output -raw agent_runtime_arn)"
echo "  aws bedrock-agentcore invoke-agent-runtime --agent-runtime-arn \$RUNTIME_ARN --payload '{\"prompt\": \"Hello\"}' --profile $AWS_PROFILE"
