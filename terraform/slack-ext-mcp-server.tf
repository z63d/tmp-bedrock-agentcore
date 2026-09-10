#------------------------------------------------------------------------------
# Slack Extended MCP Server - Lambda (Canvas operations)
#
# Provides Slack Canvas tools via Lambda target pattern.
# Auth: Slack Bot Token (requires canvases:read, canvases:write scopes)
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Lambda Deployment Package
#------------------------------------------------------------------------------

data "archive_file" "slack_ext_mcp" {
  type        = "zip"
  source_dir  = "${path.module}/../apps/lambda-slack-ext-mcp"
  output_path = "${path.module}/../apps/lambda-slack-ext-mcp/slack-ext-mcp.zip"
  excludes = [
    "tsconfig.json",
    "package-lock.json",
    "slack-ext-mcp.zip",
    "handler.ts",
    "config.ts",
    "tools",
  ]
}

#------------------------------------------------------------------------------
# IAM Role for Lambda
#------------------------------------------------------------------------------

resource "aws_iam_role" "slack_ext_mcp_lambda" {
  name = "${var.project_name}-slack-ext-mcp-lambda"

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

resource "aws_iam_role_policy" "slack_ext_mcp_lambda" {
  name = "${var.project_name}-slack-ext-mcp-policy"
  role = aws_iam_role.slack_ext_mcp_lambda.id

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
        Resource = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/lambda/${var.project_name}-slack-ext-mcp:*"
      }
    ]
  })
}

#------------------------------------------------------------------------------
# Lambda Function
#------------------------------------------------------------------------------

resource "aws_lambda_function" "slack_ext_mcp" {
  function_name = "${var.project_name}-slack-ext-mcp"
  role          = aws_iam_role.slack_ext_mcp_lambda.arn

  package_type     = "Zip"
  filename         = data.archive_file.slack_ext_mcp.output_path
  source_code_hash = data.archive_file.slack_ext_mcp.output_base64sha256
  handler          = "dist/handler.handler"
  runtime          = "nodejs24.x"
  architectures    = ["arm64"]

  memory_size = 256
  timeout     = 30

  environment {
    variables = {
      SLACK_BOT_TOKEN = var.slack_bot_token
    }
  }

  depends_on = [aws_iam_role_policy.slack_ext_mcp_lambda]
}

#------------------------------------------------------------------------------
# CloudWatch Logs
#------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "slack_ext_mcp" {
  name              = "/aws/lambda/${aws_lambda_function.slack_ext_mcp.function_name}"
  retention_in_days = 3
}
