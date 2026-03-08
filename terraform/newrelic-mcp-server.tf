#------------------------------------------------------------------------------
# New Relic MCP Server - Lambda (Remote MCP Proxy)
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# AgentCore Identity - API Key Credential Provider for New Relic
#------------------------------------------------------------------------------

resource "aws_bedrockagentcore_api_key_credential_provider" "newrelic" {
  name               = "newrelic-api-key"
  api_key_wo         = var.newrelic_api_key
  api_key_wo_version = 1
}

#------------------------------------------------------------------------------
# AgentCore Identity - Workload Identity for New Relic MCP Lambda
#------------------------------------------------------------------------------

resource "aws_bedrockagentcore_workload_identity" "newrelic_mcp" {
  name = "${var.project_name}-newrelic-mcp"
}

#------------------------------------------------------------------------------
# ECR Repository for New Relic MCP Lambda
#------------------------------------------------------------------------------

resource "aws_ecr_repository" "newrelic_mcp" {
  name                 = "${var.project_name}-newrelic-mcp"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }
}

#------------------------------------------------------------------------------
# IAM Role for New Relic MCP Lambda
#------------------------------------------------------------------------------

resource "aws_iam_role" "newrelic_mcp_lambda" {
  name = "${var.project_name}-newrelic-mcp-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "newrelic_mcp_lambda" {
  name = "${var.project_name}-newrelic-mcp-policy"
  role = aws_iam_role.newrelic_mcp_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LambdaLogging"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/lambda/${var.project_name}-newrelic-mcp:*"
      },
      {
        Sid    = "GetWorkloadAccessToken"
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:GetWorkloadAccessToken",
          "bedrock-agentcore:GetWorkloadAccessTokenForUserId"
        ]
        Resource = [
          "arn:aws:bedrock-agentcore:${var.aws_region}:${local.account_id}:workload-identity-directory/default",
          aws_bedrockagentcore_workload_identity.newrelic_mcp.workload_identity_arn
        ]
      },
      {
        Sid    = "GetResourceApiKey"
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:GetResourceApiKey"
        ]
        Resource = [
          "arn:aws:bedrock-agentcore:${var.aws_region}:${local.account_id}:workload-identity-directory/default",
          aws_bedrockagentcore_workload_identity.newrelic_mcp.workload_identity_arn,
          "arn:aws:bedrock-agentcore:${var.aws_region}:${local.account_id}:token-vault/default",
          aws_bedrockagentcore_api_key_credential_provider.newrelic.credential_provider_arn
        ]
      },
      {
        Sid    = "GetSecretValue"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_bedrockagentcore_api_key_credential_provider.newrelic.api_key_secret_arn[0].secret_arn
      }
    ]
  })
}

#------------------------------------------------------------------------------
# Lambda Function
#------------------------------------------------------------------------------

resource "aws_lambda_function" "newrelic_mcp" {
  function_name = "${var.project_name}-newrelic-mcp"
  role          = aws_iam_role.newrelic_mcp_lambda.arn

  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.newrelic_mcp.repository_url}:latest"
  architectures = ["arm64"]

  memory_size = var.newrelic_mcp_lambda_memory
  timeout     = var.newrelic_mcp_lambda_timeout

  environment {
    variables = {
      AWS_REGION_NAME                  = var.aws_region
      WORKLOAD_IDENTITY_NAME           = aws_bedrockagentcore_workload_identity.newrelic_mcp.name
      API_KEY_CREDENTIAL_PROVIDER_NAME = aws_bedrockagentcore_api_key_credential_provider.newrelic.name
      NEWRELIC_MCP_REGION              = var.newrelic_mcp_region
      NEWRELIC_DEFAULT_ACCOUNT_ID      = var.newrelic_default_account_id
    }
  }

  depends_on = [aws_iam_role_policy.newrelic_mcp_lambda]
}
