#------------------------------------------------------------------------------
# Rollbar MCP Server - Lambda
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# AgentCore Identity - API Key Credential Provider for Rollbar
#------------------------------------------------------------------------------

resource "aws_bedrockagentcore_api_key_credential_provider" "rollbar" {
  name               = "rollbar-api-key"
  api_key_wo         = var.rollbar_access_token
  api_key_wo_version = 1
}

#------------------------------------------------------------------------------
# AgentCore Identity - Workload Identity for Rollbar MCP Lambda
#------------------------------------------------------------------------------

resource "aws_bedrockagentcore_workload_identity" "rollbar_mcp" {
  name = "${var.project_name}-rollbar-mcp"
}

#------------------------------------------------------------------------------
# Lambda Deployment Package for Rollbar MCP
#------------------------------------------------------------------------------

data "archive_file" "rollbar_mcp" {
  type        = "zip"
  source_dir  = "${path.module}/../app/lambda-rollbar-mcp"
  output_path = "${path.module}/../app/lambda-rollbar-mcp/rollbar-mcp.zip"
  excludes = [
    "tsconfig.json",
    "package-lock.json",
    "rollbar-mcp.zip",
    "config.ts",
    "handler.ts",
    "tools",
    "utils",
    "types",
  ]
}

#------------------------------------------------------------------------------
# IAM Role for Rollbar MCP Lambda
#------------------------------------------------------------------------------

resource "aws_iam_role" "rollbar_mcp_lambda" {
  name = "${var.project_name}-rollbar-mcp-lambda"

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

resource "aws_iam_role_policy" "rollbar_mcp_lambda" {
  name = "${var.project_name}-rollbar-mcp-policy"
  role = aws_iam_role.rollbar_mcp_lambda.id

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
        Resource = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/lambda/${var.project_name}-rollbar-mcp:*"
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
          aws_bedrockagentcore_workload_identity.rollbar_mcp.workload_identity_arn
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
          aws_bedrockagentcore_workload_identity.rollbar_mcp.workload_identity_arn,
          "arn:aws:bedrock-agentcore:${var.aws_region}:${local.account_id}:token-vault/default",
          aws_bedrockagentcore_api_key_credential_provider.rollbar.credential_provider_arn
        ]
      },
      {
        Sid    = "GetSecretValue"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_bedrockagentcore_api_key_credential_provider.rollbar.api_key_secret_arn[0].secret_arn
      }
    ]
  })
}

#------------------------------------------------------------------------------
# Lambda Function
#------------------------------------------------------------------------------

resource "aws_lambda_function" "rollbar_mcp" {
  function_name = "${var.project_name}-rollbar-mcp"
  role          = aws_iam_role.rollbar_mcp_lambda.arn

  package_type     = "Zip"
  filename         = data.archive_file.rollbar_mcp.output_path
  source_code_hash = data.archive_file.rollbar_mcp.output_base64sha256
  handler          = "dist/handler.handler"
  runtime          = "nodejs24.x"
  architectures    = ["arm64"]

  memory_size = var.rollbar_mcp_lambda_memory
  timeout     = var.rollbar_mcp_lambda_timeout

  environment {
    variables = {
      AWS_REGION_NAME                  = var.aws_region
      WORKLOAD_IDENTITY_NAME           = aws_bedrockagentcore_workload_identity.rollbar_mcp.name
      API_KEY_CREDENTIAL_PROVIDER_NAME = aws_bedrockagentcore_api_key_credential_provider.rollbar.name
    }
  }

  depends_on = [aws_iam_role_policy.rollbar_mcp_lambda]
}

#------------------------------------------------------------------------------
# CloudWatch Logs
#------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "rollbar_mcp" {
  name              = "/aws/lambda/${aws_lambda_function.rollbar_mcp.function_name}"
  retention_in_days = 3
}
