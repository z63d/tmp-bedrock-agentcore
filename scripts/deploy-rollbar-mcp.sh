#!/bin/bash
set -e

AWS_REGION="ap-northeast-1"
AWS_PROFILE="pn-playground-admin"

# Get ECR URL from Terraform
cd "$(dirname "$0")/../terraform"
ECR_REPO=$(terraform output -raw rollbar_mcp_ecr_repository_url)

cd ../lambda/rollbar-mcp

# Build TypeScript
echo "Building TypeScript..."
npm run build

# Docker build
echo "Building Docker image for Rollbar MCP..."
docker build --platform linux/arm64 -t rollbar-mcp .

# ECR login
echo "Logging in to ECR..."
aws ecr get-login-password --region "$AWS_REGION" --profile "$AWS_PROFILE" | \
  docker login --username AWS --password-stdin "$ECR_REPO"

# Tag and push
echo "Pushing to ECR..."
docker tag rollbar-mcp:latest "$ECR_REPO:latest"
docker push "$ECR_REPO:latest"

# Update Lambda function
echo "Updating Lambda function..."
LAMBDA_NAME="k-bedrock-agentcore-rollbar-mcp"
aws lambda update-function-code \
  --function-name "$LAMBDA_NAME" \
  --image-uri "$ECR_REPO:latest" \
  --region "$AWS_REGION" \
  --profile "$AWS_PROFILE" \
  --no-cli-pager

echo ""
echo "Deployed Rollbar MCP to: $ECR_REPO:latest"
