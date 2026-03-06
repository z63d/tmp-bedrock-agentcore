#------------------------------------------------------------------------------
# CloudWatch MCP Server - Lambda
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# ECR Repository for CloudWatch MCP Lambda
#------------------------------------------------------------------------------

resource "aws_ecr_repository" "cloudwatch_mcp" {
  name                 = "${var.project_name}-cloudwatch-mcp"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }
}

#------------------------------------------------------------------------------
# IAM Role for CloudWatch MCP Lambda
#------------------------------------------------------------------------------

resource "aws_iam_role" "cloudwatch_mcp_lambda" {
  name = "${var.project_name}-cloudwatch-mcp-lambda"

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

resource "aws_iam_role_policy" "cloudwatch_mcp_lambda" {
  name = "${var.project_name}-cloudwatch-mcp-policy"
  role = aws_iam_role.cloudwatch_mcp_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarms",
          "cloudwatch:DescribeAlarmHistory",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:DescribeLogStreams",
          "logs:FilterLogEvents",
          "logs:StartQuery",
          "logs:GetQueryResults",
          "logs:StopQuery",
          "logs:DescribeQueries"
        ]
        Resource = "*"
      },
      {
        Sid    = "LambdaLogging"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/lambda/${var.project_name}-cloudwatch-mcp:*"
      }
    ]
  })
}

#------------------------------------------------------------------------------
# Lambda Function
#------------------------------------------------------------------------------

resource "aws_lambda_function" "cloudwatch_mcp" {
  function_name = "${var.project_name}-cloudwatch-mcp"
  role          = aws_iam_role.cloudwatch_mcp_lambda.arn

  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.cloudwatch_mcp.repository_url}:latest"
  architectures = ["arm64"]

  memory_size = var.cloudwatch_mcp_lambda_memory
  timeout     = var.cloudwatch_mcp_lambda_timeout

  environment {
    variables = {
      AWS_REGION_NAME = var.aws_region
    }
  }

  depends_on = [aws_iam_role_policy.cloudwatch_mcp_lambda]
}

#------------------------------------------------------------------------------
# API Gateway (REST API) - NOT USED
# AgentCore Gateway calls Lambda directly, so API Gateway is not needed.
# Keeping commented out for reference or future use.
#------------------------------------------------------------------------------

# resource "aws_api_gateway_rest_api" "cloudwatch_mcp" {
#   name        = "${var.project_name}-cloudwatch-mcp"
#   description = "CloudWatch MCP Server API for AgentCore Gateway integration"
#
#   endpoint_configuration {
#     types = ["REGIONAL"]
#   }
# }
#
# # /mcp resource
# resource "aws_api_gateway_resource" "mcp" {
#   rest_api_id = aws_api_gateway_rest_api.cloudwatch_mcp.id
#   parent_id   = aws_api_gateway_rest_api.cloudwatch_mcp.root_resource_id
#   path_part   = "mcp"
# }
#
# # POST method with IAM authorization
# resource "aws_api_gateway_method" "mcp_post" {
#   rest_api_id   = aws_api_gateway_rest_api.cloudwatch_mcp.id
#   resource_id   = aws_api_gateway_resource.mcp.id
#   http_method   = "POST"
#   authorization = "AWS_IAM"
# }
#
# # Lambda integration
# resource "aws_api_gateway_integration" "lambda" {
#   rest_api_id             = aws_api_gateway_rest_api.cloudwatch_mcp.id
#   resource_id             = aws_api_gateway_resource.mcp.id
#   http_method             = aws_api_gateway_method.mcp_post.http_method
#   integration_http_method = "POST"
#   type                    = "AWS_PROXY"
#   uri                     = aws_lambda_function.cloudwatch_mcp.invoke_arn
# }
#
# # Method response
# resource "aws_api_gateway_method_response" "mcp_post_200" {
#   rest_api_id = aws_api_gateway_rest_api.cloudwatch_mcp.id
#   resource_id = aws_api_gateway_resource.mcp.id
#   http_method = aws_api_gateway_method.mcp_post.http_method
#   status_code = "200"
#
#   response_models = {
#     "application/json" = "Empty"
#   }
# }
#
# # Deployment
# resource "aws_api_gateway_deployment" "cloudwatch_mcp" {
#   rest_api_id = aws_api_gateway_rest_api.cloudwatch_mcp.id
#
#   triggers = {
#     redeployment = sha1(jsonencode([
#       aws_api_gateway_resource.mcp.id,
#       aws_api_gateway_method.mcp_post.id,
#       aws_api_gateway_integration.lambda.id,
#     ]))
#   }
#
#   lifecycle {
#     create_before_destroy = true
#   }
#
#   depends_on = [aws_api_gateway_integration.lambda]
# }
#
# # Stage
# resource "aws_api_gateway_stage" "prod" {
#   rest_api_id   = aws_api_gateway_rest_api.cloudwatch_mcp.id
#   deployment_id = aws_api_gateway_deployment.cloudwatch_mcp.id
#   stage_name    = "prod"
#
#   access_log_settings {
#     destination_arn = aws_cloudwatch_log_group.api_gateway.arn
#     format = jsonencode({
#       requestId      = "$context.requestId"
#       ip             = "$context.identity.sourceIp"
#       caller         = "$context.identity.caller"
#       user           = "$context.identity.user"
#       requestTime    = "$context.requestTime"
#       httpMethod     = "$context.httpMethod"
#       resourcePath   = "$context.resourcePath"
#       status         = "$context.status"
#       protocol       = "$context.protocol"
#       responseLength = "$context.responseLength"
#     })
#   }
# }
#
# # CloudWatch Log Group for API Gateway
# resource "aws_cloudwatch_log_group" "api_gateway" {
#   name              = "/aws/api-gateway/${var.project_name}-cloudwatch-mcp"
#   retention_in_days = 7
# }
#
# # Lambda permission for API Gateway
# resource "aws_lambda_permission" "api_gateway" {
#   statement_id  = "AllowAPIGatewayInvoke"
#   action        = "lambda:InvokeFunction"
#   function_name = aws_lambda_function.cloudwatch_mcp.function_name
#   principal     = "apigateway.amazonaws.com"
#   source_arn    = "${aws_api_gateway_rest_api.cloudwatch_mcp.execution_arn}/*/*"
# }
