#!/bin/bash
set -e

AWS_REGION="ap-northeast-1"
AWS_PROFILE="pn-playground-admin"

# Get ECR URL from Terraform
cd "$(dirname "$0")/../terraform"
ECR_REPO=$(terraform output -raw ecr_repository_url)

cd ../app

# Build TypeScript
echo "Building TypeScript..."
npm run build

# Docker build
echo "Building Docker image..."
docker build -t bedrock-agent .

# ECR login
echo "Logging in to ECR..."
aws ecr get-login-password --region "$AWS_REGION" --profile "$AWS_PROFILE" | \
  docker login --username AWS --password-stdin "$ECR_REPO"

# Tag and push
echo "Pushing to ECR..."
docker tag bedrock-agent:latest "$ECR_REPO:latest"
docker push "$ECR_REPO:latest"

echo ""
echo "Deployed to: $ECR_REPO:latest"
echo ""
echo "To invoke the agent:"
echo "  RUNTIME_ARN=\$(cd ../terraform && terraform output -raw agent_runtime_arn)"
echo "  aws bedrock-agentcore invoke-agent-runtime --agent-runtime-arn \$RUNTIME_ARN --payload '{\"prompt\": \"Hello\"}' --profile $AWS_PROFILE"
