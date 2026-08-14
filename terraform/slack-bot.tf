#------------------------------------------------------------------------------
# Slack Bot Lambda
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# IAM Role
#------------------------------------------------------------------------------

resource "aws_iam_role" "slack_bot_lambda" {
  name = "${var.project_name}-slack-bot-lambda"

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

resource "aws_iam_role_policy" "slack_bot_lambda" {
  name = "${var.project_name}-slack-bot-policy"
  role = aws_iam_role.slack_bot_lambda.id

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
        Resource = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/lambda/${var.project_name}-slack-bot:*"
      },
      {
        Sid    = "InvokeAgentRuntime"
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:InvokeAgentRuntime"
        ]
        Resource = "${aws_bedrockagentcore_agent_runtime.main.agent_runtime_arn}*"
      },
      {
        Sid    = "SelfInvoke"
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:${local.account_id}:function:${var.project_name}-slack-bot"
      },
      {
        Sid    = "SecretsAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.slack_bot_token.arn,
          aws_secretsmanager_secret.slack_signing_secret.arn
        ]
      }
    ]
  })
}

#------------------------------------------------------------------------------
# Secrets Manager
#------------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "slack_bot_token" {
  name                    = "${var.project_name}/slack-bot-token"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "slack_bot_token" {
  secret_id     = aws_secretsmanager_secret.slack_bot_token.id
  secret_string = var.slack_bot_token
}

resource "aws_secretsmanager_secret" "slack_signing_secret" {
  name                    = "${var.project_name}/slack-signing-secret"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "slack_signing_secret" {
  secret_id     = aws_secretsmanager_secret.slack_signing_secret.id
  secret_string = var.slack_signing_secret
}

#------------------------------------------------------------------------------
# Lambda Deployment Package
#------------------------------------------------------------------------------

data "archive_file" "slack_bot" {
  type        = "zip"
  source_dir  = "${path.module}/../app/lambda-slack-bot"
  output_path = "${path.module}/../app/lambda-slack-bot/slack-bot.zip"
  excludes = [
    "tsconfig.json",
    "package-lock.json",
    "slack-bot.zip",
    "handler.ts",
  ]
}

#------------------------------------------------------------------------------
# Lambda Function
#------------------------------------------------------------------------------

resource "aws_lambda_function" "slack_bot" {
  function_name = "${var.project_name}-slack-bot"
  role          = aws_iam_role.slack_bot_lambda.arn

  package_type     = "Zip"
  filename         = data.archive_file.slack_bot.output_path
  source_code_hash = data.archive_file.slack_bot.output_base64sha256
  handler          = "dist/handler.handler"
  runtime          = "nodejs24.x"
  architectures    = ["arm64"]

  memory_size = var.slack_bot_lambda_memory
  timeout     = var.slack_bot_lambda_timeout

  environment {
    variables = {
      SLACK_BOT_TOKEN_SECRET_ARN      = aws_secretsmanager_secret.slack_bot_token.arn
      SLACK_SIGNING_SECRET_SECRET_ARN = aws_secretsmanager_secret.slack_signing_secret.arn
      AGENT_RUNTIME_ARN               = aws_bedrockagentcore_agent_runtime.main.agent_runtime_arn
      AWS_REGION_NAME                 = var.aws_region
      ALLOWED_SLACK_CHANNEL_IDS       = join(",", var.allowed_slack_channel_ids)
      ALLOWED_SLACK_USER_IDS          = join(",", var.allowed_slack_user_ids)
    }
  }

  depends_on = [aws_iam_role_policy.slack_bot_lambda]
}

#------------------------------------------------------------------------------
# Function URL (HTTPS endpoint for Slack Events API)
#------------------------------------------------------------------------------

resource "aws_lambda_function_url" "slack_bot" {
  function_name      = aws_lambda_function.slack_bot.function_name
  authorization_type = "NONE"
}

#------------------------------------------------------------------------------
# CloudWatch Logs
#------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "slack_bot" {
  name              = "/aws/lambda/${aws_lambda_function.slack_bot.function_name}"
  retention_in_days = 3
}
