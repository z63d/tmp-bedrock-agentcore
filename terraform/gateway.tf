#------------------------------------------------------------------------------
# AgentCore Gateway + CloudWatch MCP Target
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# IAM Role for AgentCore Gateway
#------------------------------------------------------------------------------

resource "aws_iam_role" "gateway" {
  count = var.enable_cloudwatch_mcp ? 1 : 0
  name  = "${var.project_name}-gateway"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "bedrock-agentcore.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = local.account_id
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "gateway" {
  count = var.enable_cloudwatch_mcp ? 1 : 0
  name  = "${var.project_name}-gateway-policy"
  role  = aws_iam_role.gateway[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvokeAPIGateway"
        Effect = "Allow"
        Action = [
          "execute-api:Invoke"
        ]
        Resource = "${aws_api_gateway_rest_api.cloudwatch_mcp[0].execution_arn}/*"
      },
      {
        Sid    = "InvokeLambda"
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.cloudwatch_mcp[0].arn
      }
    ]
  })
}

#------------------------------------------------------------------------------
# AgentCore Gateway
#------------------------------------------------------------------------------

resource "aws_bedrockagentcore_gateway" "main" {
  count    = var.enable_cloudwatch_mcp ? 1 : 0
  name     = var.project_name
  role_arn = aws_iam_role.gateway[0].arn

  # Required: Protocol type
  protocol_type = "MCP"

  # Required: Authorizer type (using IAM for simplicity)
  authorizer_type = "AWS_IAM"

  # MCP protocol configuration
  protocol_configuration {
    mcp {
      instructions       = "CloudWatch MCP Server providing observability tools for metrics, alarms, and logs analysis."
      supported_versions = ["2025-03-26"]
    }
  }

  description = "AgentCore Gateway for CloudWatch MCP Server integration"

  depends_on = [aws_iam_role_policy.gateway]
}

#------------------------------------------------------------------------------
# Gateway Target - CloudWatch MCP Server (Lambda)
#------------------------------------------------------------------------------

resource "aws_bedrockagentcore_gateway_target" "cloudwatch_mcp" {
  count              = var.enable_cloudwatch_mcp ? 1 : 0
  name               = "cloudwatch-mcp-server"
  gateway_identifier = aws_bedrockagentcore_gateway.main[0].gateway_id
  description        = "CloudWatch MCP Server Lambda target"

  # Use Gateway's IAM role for authentication
  credential_provider_configuration {
    gateway_iam_role {}
  }

  # Target configuration for Lambda-based MCP server
  # Each tool is defined individually in the toolSchema
  target_configuration {
    mcp {
      lambda {
        lambda_arn = aws_lambda_function.cloudwatch_mcp[0].arn

        tool_schema {
          inline_payload {
            name        = "get_active_alarms"
            description = "Get all active CloudWatch alarms in ALARM or INSUFFICIENT_DATA state. Useful for identifying current issues."

            input_schema {
              type = "object"

              property {
                name        = "state_value"
                type        = "string"
                description = "Filter by alarm state: ALARM, INSUFFICIENT_DATA, or OK (default: ALARM)"
                required    = false
              }

              property {
                name        = "alarm_name_prefix"
                type        = "string"
                description = "Filter alarms by name prefix"
                required    = false
              }
            }
          }

          inline_payload {
            name        = "get_metric_data"
            description = "Retrieve CloudWatch metric data for analysis. Returns time series data for specified metrics."

            input_schema {
              type = "object"

              property {
                name        = "namespace"
                type        = "string"
                description = "CloudWatch namespace (e.g., AWS/EC2, AWS/Lambda, AWS/RDS)"
                required    = true
              }

              property {
                name        = "metric_name"
                type        = "string"
                description = "Name of the metric (e.g., CPUUtilization, Invocations)"
                required    = true
              }

              property {
                name        = "period"
                type        = "integer"
                description = "Data point period in seconds (default: 300)"
                required    = false
              }

              property {
                name        = "stat"
                type        = "string"
                description = "Statistic: Average, Sum, Minimum, Maximum (default: Average)"
                required    = false
              }
            }
          }

          inline_payload {
            name        = "describe_log_groups"
            description = "List CloudWatch log groups with optional filtering."

            input_schema {
              type = "object"

              property {
                name        = "log_group_name_prefix"
                type        = "string"
                description = "Filter log groups by name prefix (e.g., /aws/lambda/)"
                required    = false
              }

              property {
                name        = "limit"
                type        = "integer"
                description = "Maximum number of log groups (default: 50)"
                required    = false
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    aws_lambda_function.cloudwatch_mcp,
    aws_bedrockagentcore_gateway.main
  ]
}
