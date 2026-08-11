#!/bin/bash
set -e

AWS_REGION="ap-northeast-1"
AWS_PROFILE="pn-playground-admin"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOCKER_CONFIG="$REPO_ROOT/.docker-tmp"

# Get ECR URL from Terraform
cd "$(dirname "$0")/../terraform"
ECR_REPO=$(terraform output -raw cloudwatch_mcp_ecr_repository_url)

cd ../lambda/cloudwatch-mcp

# Docker build
echo "Building Docker image for CloudWatch MCP..."
docker build --platform linux/arm64 -t cloudwatch-mcp .

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
docker tag cloudwatch-mcp:latest "$ECR_REPO:latest"
docker push "$ECR_REPO:latest"
rm -rf "$DOCKER_CONFIG"

# Update Lambda function
echo "Updating Lambda function..."
LAMBDA_NAME="k-bedrock-agentcore-cloudwatch-mcp"
aws lambda update-function-code \
  --function-name "$LAMBDA_NAME" \
  --image-uri "$ECR_REPO:latest" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --no-cli-pager

echo ""
echo "Deployed CloudWatch MCP to: $ECR_REPO:latest"
