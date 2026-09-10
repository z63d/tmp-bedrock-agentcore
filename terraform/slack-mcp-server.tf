#------------------------------------------------------------------------------
# Slack MCP Server - ZIP Lambda + Function URL
#
# Runs korotovsky/slack-mcp-server (Go) as a Streamable HTTP server
# on Lambda via Lambda Web Adapter (Layer). Gateway connects as mcp_server target.
#
# Auth: Slack Bot Token (passed as env var, sourced from var.slack_bot_token)
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# IAM Role for Lambda
#------------------------------------------------------------------------------

resource "aws_iam_role" "slack_mcp_lambda" {
  name = "${var.project_name}-slack-mcp-lambda"

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

resource "aws_iam_role_policy" "slack_mcp_lambda" {
  name = "${var.project_name}-slack-mcp-policy"
  role = aws_iam_role.slack_mcp_lambda.id

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
        Resource = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/lambda/${var.project_name}-slack-mcp:*"
      }
    ]
  })
}

#------------------------------------------------------------------------------
# Lambda Deployment Package
#------------------------------------------------------------------------------

data "archive_file" "slack_mcp" {
  type        = "zip"
  source_dir  = "${path.module}/../apps/lambda-slack-mcp"
  output_path = "${path.module}/../apps/lambda-slack-mcp/lambda.zip"
  excludes = [
    "lambda.zip",
    ".build",
  ]
}

#------------------------------------------------------------------------------
# Lambda Function (ZIP with Lambda Web Adapter Layer)
#------------------------------------------------------------------------------

resource "aws_lambda_function" "slack_mcp" {
  function_name = "${var.project_name}-slack-mcp"
  role          = aws_iam_role.slack_mcp_lambda.arn
  package_type  = "Zip"
  filename      = data.archive_file.slack_mcp.output_path
  handler       = "bootstrap"
  runtime       = "provided.al2023"
  architectures = ["arm64"]
  memory_size   = 256
  timeout       = 30

  source_code_hash = data.archive_file.slack_mcp.output_base64sha256

  layers = [
    "arn:aws:lambda:${var.aws_region}:753240598075:layer:LambdaAdapterLayerArm64:28"
  ]

  environment {
    variables = {
      AWS_LWA_PORT                                 = "8080"
      AWS_LWA_READINESS_CHECK_PORT                 = "8080"
      AWS_LWA_READINESS_CHECK_PATH                 = "/"
      AWS_LWA_READINESS_CHECK_MIN_UNHEALTHY_STATUS = "500"
      AWS_LWA_INVOKE_MODE                          = "buffered"
      AWS_LWA_STARTUP_TIMEOUT_MS                   = "10000"
      SLACK_MCP_HOST                               = "0.0.0.0"
      SLACK_MCP_PORT                               = "8080"
      SLACK_MCP_XOXB_TOKEN                         = var.slack_bot_token
      SLACK_MCP_ADD_MESSAGE_TOOL                   = "true"
      SLACK_MCP_REACTION_TOOL                      = "true"
      SLACK_MCP_USERS_CACHE                        = "/tmp/users_cache.json"
      SLACK_MCP_CHANNELS_CACHE                     = "/tmp/channels_cache.json"
      HOME                                         = "/tmp"
    }
  }

  depends_on = [aws_iam_role_policy.slack_mcp_lambda]
}

#------------------------------------------------------------------------------
# Lambda Function URL (IAM auth)
#------------------------------------------------------------------------------

resource "aws_lambda_function_url" "slack_mcp" {
  function_name      = aws_lambda_function.slack_mcp.function_name
  authorization_type = "AWS_IAM"
  invoke_mode        = "BUFFERED"
}

resource "aws_lambda_permission" "slack_mcp_function_url" {
  statement_id           = "AllowGatewayFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.slack_mcp.function_name
  principal              = aws_iam_role.gateway.arn
  function_url_auth_type = "AWS_IAM"
}

#------------------------------------------------------------------------------
# CloudWatch Logs
#------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "slack_mcp" {
  name              = "/aws/lambda/${var.project_name}-slack-mcp"
  retention_in_days = 3
}

# Gateway Target is defined in bedrock-agentcore-gateway.tf
