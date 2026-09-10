#------------------------------------------------------------------------------
# AgentCore Gateway + MCP Targets
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# IAM Role for AgentCore Gateway
#------------------------------------------------------------------------------

resource "aws_iam_role" "gateway" {
  name = "${var.project_name}-gateway"

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
  name = "${var.project_name}-gateway-policy"
  role = aws_iam_role.gateway.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # API Gateway is not used - AgentCore Gateway calls Lambda directly
      # {
      #   Sid    = "InvokeAPIGateway"
      #   Effect = "Allow"
      #   Action = [
      #     "execute-api:Invoke"
      #   ]
      #   Resource = "${aws_api_gateway_rest_api.cloudwatch_mcp.execution_arn}/*"
      # },
      {
        Sid    = "InvokeLambda"
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = [
          aws_lambda_function.rollbar_mcp.arn,
          aws_lambda_function.slack_ext_mcp.arn,
        ]
      },
      {
        Sid    = "InvokeFunctionUrl"
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunctionUrl"
        ]
        Resource = [
          aws_lambda_function.google_workspace_mcp.arn,
          aws_lambda_function.slack_mcp.arn,
        ]
      },
      {
        Sid    = "GetWorkloadAccessToken"
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:GetWorkloadAccessToken"
        ]
        Resource = [
          "arn:aws:bedrock-agentcore:${var.aws_region}:${local.account_id}:workload-identity-directory/default",
          "arn:aws:bedrock-agentcore:${var.aws_region}:${local.account_id}:workload-identity-directory/default/workload-identity/${var.project_name}-*"
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
          "arn:aws:bedrock-agentcore:${var.aws_region}:${local.account_id}:workload-identity-directory/default/workload-identity/${var.project_name}-*",
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
        Resource = [
          aws_bedrockagentcore_api_key_credential_provider.newrelic.api_key_secret_arn[0].secret_arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "gateway_readonly" {
  role       = aws_iam_role.gateway.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

#------------------------------------------------------------------------------
# AgentCore Gateway
#------------------------------------------------------------------------------

resource "aws_bedrockagentcore_gateway" "main" {
  name     = var.project_name
  role_arn = aws_iam_role.gateway.arn

  # Required: Protocol type
  protocol_type = "MCP"

  # Required: Authorizer type (using IAM for simplicity)
  authorizer_type = "AWS_IAM"

  # MCP protocol configuration
  protocol_configuration {
    mcp {
      instructions       = "MCP Gateway providing various tools for AWS operations and observability."
      supported_versions = ["2025-03-26"]
    }
  }

  description = "AgentCore MCP Gateway for tool integrations"

  depends_on = [aws_iam_role_policy.gateway]
}

#------------------------------------------------------------------------------
# CloudWatch Logs for AgentCore Gateway
#------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "gateway" {
  name              = "/aws/vendedlogs/bedrock-agentcore/gateway/APPLICATION_LOGS/${aws_bedrockagentcore_gateway.main.gateway_id}"
  retention_in_days = 3
}

resource "aws_cloudwatch_log_delivery_source" "gateway" {
  name         = "${var.project_name}-gateway"
  log_type     = "APPLICATION_LOGS"
  resource_arn = aws_bedrockagentcore_gateway.main.gateway_arn
}

resource "aws_cloudwatch_log_delivery_destination" "gateway" {
  name = "${var.project_name}-gateway"

  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.gateway.arn
  }
}

resource "aws_cloudwatch_log_delivery" "gateway" {
  delivery_source_name     = aws_cloudwatch_log_delivery_source.gateway.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.gateway.arn
}

#------------------------------------------------------------------------------
# Gateway Target - Rollbar MCP Server (Lambda)
#------------------------------------------------------------------------------

resource "aws_bedrockagentcore_gateway_target" "rollbar_mcp" {
  name               = "rollbar-mcp-server"
  gateway_identifier = aws_bedrockagentcore_gateway.main.gateway_id
  description        = "Rollbar MCP Server Lambda target for error tracking and monitoring"

  # Use Gateway's IAM role for authentication
  credential_provider_configuration {
    gateway_iam_role {}
  }

  # Target configuration for Lambda-based MCP server
  target_configuration {
    mcp {
      lambda {
        lambda_arn = aws_lambda_function.rollbar_mcp.arn

        tool_schema {
          # get-item-details
          inline_payload {
            name        = "get-item-details"
            description = "Get detailed information about a Rollbar item by its counter, including the last occurrence data"

            input_schema {
              type = "object"

              property {
                name        = "counter"
                type        = "integer"
                description = "Rollbar item counter"
                required    = true
              }

              property {
                name        = "max_tokens"
                type        = "integer"
                description = "Maximum tokens for occurrence data in response (default: 20000)"
                required    = false
              }
            }
          }

          # get-deployments
          inline_payload {
            name        = "get-deployments"
            description = "Get deployment status and information for a Rollbar project"

            input_schema {
              type = "object"

              property {
                name        = "limit"
                type        = "integer"
                description = "Number of deployments to retrieve"
                required    = true
              }
            }
          }

          # get-version
          inline_payload {
            name        = "get-version"
            description = "Get version data and information for a Rollbar project"

            input_schema {
              type = "object"

              property {
                name        = "version"
                type        = "string"
                description = "Version string (e.g. git sha)"
                required    = true
              }

              property {
                name        = "environment"
                type        = "string"
                description = "Environment name (default: production)"
                required    = false
              }
            }
          }

          # get-top-items
          inline_payload {
            name        = "get-top-items"
            description = "Get list of top active items in the Rollbar project for the last 24 hours"

            input_schema {
              type = "object"

              property {
                name        = "environment"
                type        = "string"
                description = "Environment name (default: production)"
                required    = false
              }
            }
          }

          # list-items
          inline_payload {
            name        = "list-items"
            description = "List all items in the Rollbar project with optional search and filtering"

            input_schema {
              type = "object"

              property {
                name        = "status"
                type        = "string"
                description = "Filter by item status: active, resolved, muted, archived (default: active)"
                required    = false
              }

              property {
                name        = "environment"
                type        = "string"
                description = "Filter by environment (default: production)"
                required    = false
              }

              property {
                name        = "page"
                type        = "integer"
                description = "Page number for pagination (default: 1)"
                required    = false
              }

              property {
                name        = "limit"
                type        = "integer"
                description = "Number of items per page (default: 20, max: 5000)"
                required    = false
              }

              property {
                name        = "query"
                type        = "string"
                description = "Search query to filter items by title or content"
                required    = false
              }
            }
          }

          # update-item
          inline_payload {
            name        = "update-item"
            description = "Update an item in Rollbar (status, level, title, assignment, etc.)"

            input_schema {
              type = "object"

              property {
                name        = "itemId"
                type        = "integer"
                description = "The ID of the item to update"
                required    = true
              }

              property {
                name        = "status"
                type        = "string"
                description = "The new status: active, resolved, muted, archived"
                required    = false
              }

              property {
                name        = "level"
                type        = "string"
                description = "The new level: debug, info, warning, error, critical"
                required    = false
              }

              property {
                name        = "title"
                type        = "string"
                description = "The new title for the item"
                required    = false
              }
            }
          }

          # get-replay
          inline_payload {
            name        = "get-replay"
            description = "Get session replay data for a specific replay in Rollbar"

            input_schema {
              type = "object"

              property {
                name        = "environment"
                type        = "string"
                description = "Environment name (e.g., production)"
                required    = true
              }

              property {
                name        = "sessionId"
                type        = "string"
                description = "Session identifier that owns the replay"
                required    = true
              }

              property {
                name        = "replayId"
                type        = "string"
                description = "Replay identifier to retrieve"
                required    = true
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    aws_lambda_function.rollbar_mcp,
    aws_bedrockagentcore_gateway.main
  ]
}

#------------------------------------------------------------------------------
# Gateway Target - New Relic MCP Server (official MCP endpoint)
#------------------------------------------------------------------------------

resource "aws_bedrockagentcore_gateway_target" "newrelic_mcp" {
  name               = "newrelic-mcp-server"
  gateway_identifier = aws_bedrockagentcore_gateway.main.gateway_id
  description        = "New Relic official MCP server"

  credential_provider_configuration {
    api_key {
      provider_arn              = aws_bedrockagentcore_api_key_credential_provider.newrelic.credential_provider_arn
      credential_location       = "HEADER"
      credential_parameter_name = "api-key"
    }
  }

  target_configuration {
    mcp {
      mcp_server {
        endpoint = "https://mcp.newrelic.com/mcp/"
      }
    }
  }

  depends_on = [aws_bedrockagentcore_gateway.main]
}

#------------------------------------------------------------------------------
# Gateway Target - AWS MCP Server (official AWS remote MCP endpoint)
#------------------------------------------------------------------------------

resource "aws_bedrockagentcore_gateway_target" "aws_mcp" {
  name               = "aws-mcp-server"
  gateway_identifier = aws_bedrockagentcore_gateway.main.gateway_id
  description        = "AWS official MCP server for calling AWS APIs"

  credential_provider_configuration {
    gateway_iam_role {
      service = "aws-mcp"
      region  = "us-east-1"
    }
  }

  target_configuration {
    mcp {
      mcp_server {
        endpoint     = "https://aws-mcp.us-east-1.api.aws/mcp"
        listing_mode = "DEFAULT"
      }
    }
  }

  depends_on = [aws_bedrockagentcore_gateway.main]
}

#------------------------------------------------------------------------------
# Gateway Target - Slack Extended MCP Server (Canvas operations, Lambda)
#------------------------------------------------------------------------------

resource "aws_bedrockagentcore_gateway_target" "slack_ext_mcp" {
  name               = "slack-ext-mcp-server"
  gateway_identifier = aws_bedrockagentcore_gateway.main.gateway_id
  description        = "Slack Extended MCP Server - Canvas create/edit/delete/access operations"

  credential_provider_configuration {
    gateway_iam_role {}
  }

  target_configuration {
    mcp {
      lambda {
        lambda_arn = aws_lambda_function.slack_ext_mcp.arn

        tool_schema {
          inline_payload {
            name        = "canvas-create"
            description = "Create a new standalone Slack canvas with optional markdown content"

            input_schema {
              type = "object"

              property {
                name        = "title"
                type        = "string"
                description = "Canvas title"
                required    = false
              }

              property {
                name        = "markdown"
                type        = "string"
                description = "Initial content in markdown format"
                required    = false
              }

              property {
                name        = "channel_id"
                type        = "string"
                description = "Channel ID to tab the canvas in"
                required    = false
              }
            }
          }

          inline_payload {
            name        = "canvas-edit"
            description = "Edit a Slack canvas (insert, replace, delete content or rename)"

            input_schema {
              type = "object"

              property {
                name        = "canvas_id"
                type        = "string"
                description = "Canvas ID (F-prefixed)"
                required    = true
              }

              property {
                name        = "operation"
                type        = "string"
                description = "Edit operation: insert_at_start, insert_at_end, insert_after, insert_before, replace, delete, rename"
                required    = true
              }

              property {
                name        = "markdown"
                type        = "string"
                description = "Content in markdown format (for insert/replace operations)"
                required    = false
              }

              property {
                name        = "section_id"
                type        = "string"
                description = "Target section ID (required for insert_after, insert_before, delete)"
                required    = false
              }

              property {
                name        = "title"
                type        = "string"
                description = "New title (for rename operation)"
                required    = false
              }
            }
          }

          inline_payload {
            name        = "canvas-delete"
            description = "Permanently delete a Slack canvas (cannot be undone)"

            input_schema {
              type = "object"

              property {
                name        = "canvas_id"
                type        = "string"
                description = "Canvas ID to delete"
                required    = true
              }
            }
          }

          inline_payload {
            name        = "canvas-sections-lookup"
            description = "Find sections in a canvas by type or text content"

            input_schema {
              type = "object"

              property {
                name        = "canvas_id"
                type        = "string"
                description = "Canvas ID"
                required    = true
              }

              property {
                name        = "criteria"
                type        = "object"
                description = "Search criteria with optional section_types (array) and contains_text (string)"
                required    = true
              }
            }
          }

          inline_payload {
            name        = "canvas-access-set"
            description = "Set access permissions on a canvas for channels or users"

            input_schema {
              type = "object"

              property {
                name        = "canvas_id"
                type        = "string"
                description = "Canvas ID"
                required    = true
              }

              property {
                name        = "access_level"
                type        = "string"
                description = "Access level: read, write, or owner"
                required    = true
              }

              property {
                name        = "channel_ids"
                type        = "string"
                description = "Comma-separated channel IDs to grant access (mutually exclusive with user_ids)"
                required    = false
              }

              property {
                name        = "user_ids"
                type        = "string"
                description = "Comma-separated user IDs to grant access (mutually exclusive with channel_ids)"
                required    = false
              }
            }
          }

          inline_payload {
            name        = "channel-canvas-create"
            description = "Create a channel canvas (resource hub). One per channel maximum."

            input_schema {
              type = "object"

              property {
                name        = "channel_id"
                type        = "string"
                description = "Channel ID"
                required    = true
              }

              property {
                name        = "title"
                type        = "string"
                description = "Canvas title"
                required    = false
              }

              property {
                name        = "markdown"
                type        = "string"
                description = "Initial content in markdown format"
                required    = false
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    aws_lambda_function.slack_ext_mcp,
    aws_bedrockagentcore_gateway.main
  ]
}

#------------------------------------------------------------------------------
# Gateway Target - Slack MCP Server (remote MCP endpoint via Lambda Function URL)
#------------------------------------------------------------------------------

resource "aws_bedrockagentcore_gateway_target" "slack_mcp" {
  name               = "slack-mcp-server"
  gateway_identifier = aws_bedrockagentcore_gateway.main.gateway_id
  description        = "Slack MCP server (channels, messages, reactions, users, search) via Lambda"

  credential_provider_configuration {
    gateway_iam_role {
      service = "lambda"
      region  = var.aws_region
    }
  }

  target_configuration {
    mcp {
      mcp_server {
        endpoint     = "${aws_lambda_function_url.slack_mcp.function_url}mcp"
        listing_mode = "DEFAULT"
      }
    }
  }

  depends_on = [aws_bedrockagentcore_gateway.main]
}

#------------------------------------------------------------------------------
# Gateway Target - Google Workspace MCP Server (remote MCP endpoint via Lambda Function URL)
#------------------------------------------------------------------------------

resource "aws_bedrockagentcore_gateway_target" "google_workspace_mcp" {
  name               = "google-workspace-mcp-server"
  gateway_identifier = aws_bedrockagentcore_gateway.main.gateway_id
  description        = "Google Workspace MCP server (Drive, Docs, Sheets, Slides) via Lambda"

  credential_provider_configuration {
    gateway_iam_role {
      service = "lambda"
      region  = var.aws_region
    }
  }

  target_configuration {
    mcp {
      mcp_server {
        endpoint     = "${aws_lambda_function_url.google_workspace_mcp.function_url}mcp"
        listing_mode = "DEFAULT"
      }
    }
  }

  depends_on = [aws_bedrockagentcore_gateway.main]
}
