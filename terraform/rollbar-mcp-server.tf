#------------------------------------------------------------------------------
# Rollbar MCP Server - Lambda
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# SSM Parameter for Rollbar Access Token
#------------------------------------------------------------------------------

resource "aws_ssm_parameter" "rollbar_access_token" {
  name        = "/rollbar/mcp/access-token"
  description = "Rollbar API access token for MCP server"
  type        = "SecureString"
  value       = var.rollbar_access_token

  lifecycle {
    ignore_changes = [value]
  }
}

#------------------------------------------------------------------------------
# ECR Repository for Rollbar MCP Lambda
#------------------------------------------------------------------------------

resource "aws_ecr_repository" "rollbar_mcp" {
  name                 = "${var.project_name}-rollbar-mcp"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }
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
        Sid    = "SSMGetParameter"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter"
        ]
        Resource = "arn:aws:ssm:${var.aws_region}:${local.account_id}:parameter/rollbar/mcp/access-token"
      },
      {
        Sid    = "LambdaLogging"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/lambda/${var.project_name}-rollbar-mcp:*"
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

  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.rollbar_mcp.repository_url}:latest"
  architectures = ["arm64"]

  memory_size = var.rollbar_mcp_lambda_memory
  timeout     = var.rollbar_mcp_lambda_timeout

  environment {
    variables = {
      AWS_REGION_NAME = var.aws_region
    }
  }

  depends_on = [aws_iam_role_policy.rollbar_mcp_lambda]
}
