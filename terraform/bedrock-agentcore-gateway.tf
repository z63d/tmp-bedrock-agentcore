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
          aws_lambda_function.cloudwatch_mcp.arn,
          aws_lambda_function.rollbar_mcp.arn,
          aws_lambda_function.newrelic_mcp.arn
        ]
      }
    ]
  })
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
# Gateway Target - CloudWatch MCP Server (Lambda)
#------------------------------------------------------------------------------

resource "aws_bedrockagentcore_gateway_target" "cloudwatch_mcp" {
  name               = "cloudwatch-mcp-server"
  gateway_identifier = aws_bedrockagentcore_gateway.main.gateway_id
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
        lambda_arn = aws_lambda_function.cloudwatch_mcp.arn

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

          inline_payload {
            name        = "analyze_metric"
            description = "Analyze a CloudWatch metric for trends, anomalies, and statistics. Provides summary statistics and identifies patterns."

            input_schema {
              type = "object"

              property {
                name        = "namespace"
                type        = "string"
                description = "CloudWatch namespace"
                required    = true
              }

              property {
                name        = "metric_name"
                type        = "string"
                description = "Name of the metric to analyze"
                required    = true
              }

              property {
                name        = "hours"
                type        = "integer"
                description = "Number of hours to analyze (default: 24)"
                required    = false
              }
            }
          }

          inline_payload {
            name        = "get_alarm_history"
            description = "Get history of state changes for a specific alarm. Useful for understanding alarm patterns."

            input_schema {
              type = "object"

              property {
                name        = "alarm_name"
                type        = "string"
                description = "Name of the alarm to get history for"
                required    = true
              }

              property {
                name        = "history_item_type"
                type        = "string"
                description = "Type of history items: ConfigurationUpdate, StateUpdate, Action (default: StateUpdate)"
                required    = false
              }

              property {
                name        = "max_records"
                type        = "integer"
                description = "Maximum number of history records (default: 50)"
                required    = false
              }
            }
          }

          inline_payload {
            name        = "analyze_log_group"
            description = "Analyze a CloudWatch log group for error patterns and anomalies within a time window."

            input_schema {
              type = "object"

              property {
                name        = "log_group_name"
                type        = "string"
                description = "Name of the log group to analyze"
                required    = true
              }

              property {
                name        = "hours"
                type        = "integer"
                description = "Number of hours to analyze (default: 1)"
                required    = false
              }

              property {
                name        = "filter_pattern"
                type        = "string"
                description = "CloudWatch Logs filter pattern (e.g., ERROR, Exception)"
                required    = false
              }
            }
          }

          inline_payload {
            name        = "execute_log_insights_query"
            description = "Execute a CloudWatch Logs Insights query for advanced log analysis."

            input_schema {
              type = "object"

              property {
                name        = "log_group_name"
                type        = "string"
                description = "Name of the log group to query"
                required    = true
              }

              property {
                name        = "query_string"
                type        = "string"
                description = "Logs Insights query string (e.g., 'fields @timestamp, @message | filter @message like /ERROR/')"
                required    = true
              }

              property {
                name        = "start_time"
                type        = "string"
                description = "ISO8601 start time (default: 1 hour ago)"
                required    = false
              }

              property {
                name        = "end_time"
                type        = "string"
                description = "ISO8601 end time (default: now)"
                required    = false
              }

              property {
                name        = "limit"
                type        = "integer"
                description = "Maximum number of results (default: 100)"
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
# Gateway Target - New Relic MCP Server (Lambda Proxy)
#------------------------------------------------------------------------------

resource "aws_bedrockagentcore_gateway_target" "newrelic_mcp" {
  name               = "newrelic-mcp-server"
  gateway_identifier = aws_bedrockagentcore_gateway.main.gateway_id
  description        = "New Relic MCP Server Lambda proxy for observability data"

  # Use Gateway's IAM role for authentication
  credential_provider_configuration {
    gateway_iam_role {}
  }

  # Target configuration for Lambda-based MCP proxy
  target_configuration {
    mcp {
      lambda {
        lambda_arn = aws_lambda_function.newrelic_mcp.arn

        tool_schema {
          # Account Discovery
          inline_payload {
            name        = "list_available_new_relic_accounts"
            description = "Lists all New Relic account IDs accessible to the authenticated user"

            input_schema {
              type = "object"
            }
          }

          # Entity and Account Management
          inline_payload {
            name        = "get_entity"
            description = "Fetch New Relic entities by GUID or search by name pattern"

            input_schema {
              type = "object"

              property {
                name        = "entity_guid"
                type        = "string"
                description = "The exact entity ID when you know it"
                required    = false
              }

              property {
                name        = "name_pattern"
                type        = "string"
                description = "Search pattern with wildcards: 'webapp' (contains), 'prod%' (starts with), '%api' (ends with)"
                required    = false
              }
            }
          }

          inline_payload {
            name        = "list_entity_types"
            description = "List the complete catalog of New Relic entity types with domain/type definitions"

            input_schema {
              type = "object"
            }
          }

          inline_payload {
            name        = "list_related_entities"
            description = "List entities 1 hop away (related) from a given entity GUID"

            input_schema {
              type = "object"

              property {
                name        = "entity_guid"
                type        = "string"
                description = "The GUID of the entity to find related entities for"
                required    = true
              }
            }
          }

          # Data Access
          inline_payload {
            name        = "execute_nrql_query"
            description = "Execute an NRQL query against NRDB"

            input_schema {
              type = "object"

              property {
                name        = "account_id"
                type        = "integer"
                description = "New Relic account ID"
                required    = true
              }

              property {
                name        = "nrql_query"
                type        = "string"
                description = "NRQL query string. Example: SELECT count(*) FROM Transaction WHERE appName = 'MyApp' SINCE 1 hour ago"
                required    = true
              }
            }
          }

          # Alerting and Monitoring
          # Alerting and Monitoring
          inline_payload {
            name        = "list_recent_issues"
            description = "Lists all recent (last 24 hours) issues in New Relic for the specified account"

            input_schema {
              type = "object"

              property {
                name        = "account_id"
                type        = "integer"
                description = "New Relic account ID"
                required    = true
              }

              property {
                name        = "cursor"
                type        = "string"
                description = "Pagination cursor from previous response"
                required    = false
              }
            }
          }

          # Performance Analytics
          inline_payload {
            name        = "analyze_golden_metrics"
            description = "Analyze golden metrics (throughput, response time, errors) for an entity"

            input_schema {
              type = "object"

              property {
                name        = "entity_guid"
                type        = "string"
                description = "Entity GUID to analyze"
                required    = true
              }

              property {
                name        = "time_period"
                type        = "string"
                description = "Time period (e.g., 'last 30 minutes')"
                required    = false
              }
            }
          }

          inline_payload {
            name        = "list_recent_logs"
            description = "List recent logs from New Relic for the specified account and entity GUID"

            input_schema {
              type = "object"

              property {
                name        = "account_id"
                type        = "integer"
                description = "New Relic account ID"
                required    = true
              }

              property {
                name        = "entity_guid"
                type        = "string"
                description = "Entity GUID to get logs for"
                required    = true
              }

              property {
                name        = "number_of_logs"
                type        = "integer"
                description = "The number of recent logs to retrieve"
                required    = true
              }

              property {
                name        = "history_period_minutes"
                type        = "integer"
                description = "The time period in minutes to look back for logs"
                required    = true
              }
            }
          }

          # Advanced Analysis
          inline_payload {
            name        = "analyze_deployment_impact"
            description = "Analyze the performance impact of a deployment on a specific entity"

            input_schema {
              type = "object"

              property {
                name        = "entity_guid"
                type        = "string"
                description = "Entity GUID to analyze"
                required    = true
              }

              property {
                name        = "deployment_id"
                type        = "string"
                description = "Deployment ID to analyze"
                required    = false
              }
            }
          }

          inline_payload {
            name        = "generate_alert_insights_report"
            description = "Generate an alert intelligence analysis report for a specific issue"

            input_schema {
              type = "object"

              property {
                name        = "issue_id"
                type        = "string"
                description = "Issue ID to generate report for"
                required    = true
              }

              property {
                name        = "account_id"
                type        = "integer"
                description = "New Relic account ID"
                required    = true
              }
            }
          }

          inline_payload {
            name        = "generate_user_impact_report"
            description = "Generate an end-user impact analysis report for a specific issue"

            input_schema {
              type = "object"

              property {
                name        = "issue_id"
                type        = "string"
                description = "Issue ID to generate report for"
                required    = true
              }

              property {
                name        = "account_id"
                type        = "integer"
                description = "New Relic account ID"
                required    = true
              }
            }
          }

          # Utilities
          inline_payload {
            name        = "convert_time_period_to_epoch_ms"
            description = "Convert a time period (e.g., 'last 30 minutes') to epoch milliseconds"

            input_schema {
              type = "object"

              property {
                name        = "time_period"
                type        = "string"
                description = "Time period to convert"
                required    = true
              }
            }
          }

          inline_payload {
            name        = "get_dashboard"
            description = "Fetch details about a specific dashboard"

            input_schema {
              type = "object"

              property {
                name        = "dashboard_guid"
                type        = "string"
                description = "Dashboard GUID to fetch"
                required    = true
              }
            }
          }

          # Alerting
          inline_payload {
            name        = "list_alert_policies"
            description = "Lists alert policies for the specified account, optionally filtering by policy name"

            input_schema {
              type = "object"

              property {
                name        = "account_id"
                type        = "integer"
                description = "New Relic account ID"
                required    = true
              }

              property {
                name        = "policy_name"
                type        = "string"
                description = "Policy name filter (optional, uses partial matching)"
                required    = false
              }

              property {
                name        = "cursor"
                type        = "string"
                description = "Pagination cursor from previous response"
                required    = false
              }
            }
          }

          inline_payload {
            name        = "list_alert_conditions"
            description = "Retrieves alert condition details for a specific alert policy"

            input_schema {
              type = "object"

              property {
                name        = "account_id"
                type        = "integer"
                description = "New Relic account ID"
                required    = true
              }

              property {
                name        = "policyId"
                type        = "integer"
                description = "The ID of the alert policy to query"
                required    = true
              }
            }
          }

          inline_payload {
            name        = "search_incident"
            description = "Retrieve all alert incident events (both open and close events) from New Relic with flexible filtering"

            input_schema {
              type = "object"

              property {
                name        = "account_id"
                type        = "integer"
                description = "New Relic account ID"
                required    = true
              }

              property {
                name        = "entity_guid"
                type        = "string"
                description = "The GUID of the entity to look up alert events for"
                required    = false
              }

              property {
                name        = "issue_id"
                type        = "string"
                description = "The issue ID to look up alert events for"
                required    = false
              }

              property {
                name        = "start_time_ms"
                type        = "integer"
                description = "Start time in epoch ms format"
                required    = false
              }

              property {
                name        = "end_time_ms"
                type        = "integer"
                description = "End time in epoch ms format"
                required    = false
              }
            }
          }

          # Synthetics
          inline_payload {
            name        = "list_synthetic_monitors"
            description = "Lists synthetic monitors for the specified account"

            input_schema {
              type = "object"

              property {
                name        = "account_id"
                type        = "integer"
                description = "New Relic account ID"
                required    = true
              }

              property {
                name        = "limit"
                type        = "integer"
                description = "Maximum number of monitors to return (default: 50)"
                required    = false
              }

              property {
                name        = "cursor"
                type        = "string"
                description = "Pagination cursor from previous response"
                required    = false
              }
            }
          }

          # Dashboards
          inline_payload {
            name        = "list_dashboards"
            description = "Lists all dashboards for a New Relic account"

            input_schema {
              type = "object"

              property {
                name        = "account_id"
                type        = "integer"
                description = "New Relic account ID"
                required    = true
              }

              property {
                name        = "limit"
                type        = "integer"
                description = "Maximum number of dashboards to return (default: 50)"
                required    = false
              }

              property {
                name        = "cursor"
                type        = "string"
                description = "Pagination cursor from previous response"
                required    = false
              }
            }
          }

          # Entity Search
          inline_payload {
            name        = "search_entity_with_tag"
            description = "Searches for entities in New Relic using tag key and value pairs"

            input_schema {
              type = "object"

              property {
                name        = "tag_key"
                type        = "string"
                description = "The tag key to filter entities (e.g., 'environment', 'team')"
                required    = false
              }

              property {
                name        = "tag_value"
                type        = "string"
                description = "The tag value to filter entities (e.g., 'production', 'backend')"
                required    = false
              }

              property {
                name        = "limit"
                type        = "integer"
                description = "Maximum number of entities to return (default: 50)"
                required    = false
              }

              property {
                name        = "cursor"
                type        = "string"
                description = "Pagination cursor from previous response"
                required    = false
              }
            }
          }

          # Natural Language Query
          inline_payload {
            name        = "natural_language_to_nrql_query"
            description = "Converts a natural language request into an NRQL query and executes it"

            input_schema {
              type = "object"

              property {
                name        = "user_request"
                type        = "string"
                description = "Natural language request (e.g., 'Show me error rate for my app in the last hour')"
                required    = true
              }

              property {
                name        = "account_id"
                type        = "integer"
                description = "New Relic account ID"
                required    = true
              }
            }
          }

          # Analysis Tools
          inline_payload {
            name        = "analyze_entity_logs"
            description = "Analyzes application logs to identify error patterns, anomalous behavior, and recurring issues"

            input_schema {
              type = "object"

              property {
                name        = "entity_guid"
                type        = "string"
                description = "The unique New Relic GUID of the entity"
                required    = true
              }

              property {
                name        = "start_time_ms"
                type        = "integer"
                description = "Epoch timestamp in milliseconds for start of analysis"
                required    = true
              }

              property {
                name        = "end_time_ms"
                type        = "integer"
                description = "Epoch timestamp in milliseconds for end of analysis"
                required    = false
              }
            }
          }

          inline_payload {
            name        = "analyze_transactions"
            description = "Analyzes transactions for a specific entity, identifying slow and error-prone transactions"

            input_schema {
              type = "object"

              property {
                name        = "entity_guid"
                type        = "string"
                description = "The unique New Relic GUID of the entity"
                required    = true
              }

              property {
                name        = "start_time_ms"
                type        = "integer"
                description = "Epoch timestamp in milliseconds for start of analysis"
                required    = true
              }

              property {
                name        = "end_time_ms"
                type        = "integer"
                description = "Epoch timestamp in milliseconds for end of analysis"
                required    = false
              }

              property {
                name        = "error_transaction_limit"
                type        = "integer"
                description = "Maximum number of error transactions to include"
                required    = true
              }
            }
          }

          inline_payload {
            name        = "analyze_threads"
            description = "Analyzes thread metric data including thread state, CPU usage, and memory consumption"

            input_schema {
              type = "object"

              property {
                name        = "entity_guid"
                type        = "string"
                description = "The unique New Relic GUID of the entity"
                required    = true
              }

              property {
                name        = "start_time_ms"
                type        = "integer"
                description = "Epoch timestamp in milliseconds for start of analysis"
                required    = true
              }

              property {
                name        = "end_time_ms"
                type        = "integer"
                description = "Epoch timestamp in milliseconds for end of analysis"
                required    = false
              }
            }
          }

          inline_payload {
            name        = "analyze_kafka_metrics"
            description = "Analyzes Kafka metrics including consumer lag, producer throughput, and message latency"

            input_schema {
              type = "object"

              property {
                name        = "entity_guid"
                type        = "string"
                description = "The unique New Relic GUID of the Kafka entity"
                required    = true
              }

              property {
                name        = "start_time_ms"
                type        = "integer"
                description = "Epoch timestamp in milliseconds for start of analysis"
                required    = true
              }

              property {
                name        = "end_time_ms"
                type        = "integer"
                description = "Epoch timestamp in milliseconds for end of analysis"
                required    = false
              }
            }
          }

          # Error Groups
          inline_payload {
            name        = "list_entity_error_groups"
            description = "Fetches error groups for a specific entity from the Errors Inbox"

            input_schema {
              type = "object"

              property {
                name        = "entity_guid"
                type        = "string"
                description = "The unique New Relic GUID of the entity"
                required    = true
              }

              property {
                name        = "start_time_ms"
                type        = "integer"
                description = "Epoch timestamp in milliseconds for start of analysis"
                required    = true
              }

              property {
                name        = "end_time_ms"
                type        = "integer"
                description = "Epoch timestamp in milliseconds for end of analysis"
                required    = false
              }
            }
          }

          # Garbage Collection
          inline_payload {
            name        = "list_garbage_collection_metrics"
            description = "Retrieves garbage collection and memory metrics for an entity"

            input_schema {
              type = "object"

              property {
                name        = "entity_guid"
                type        = "string"
                description = "The unique New Relic GUID of the entity"
                required    = false
              }

              property {
                name        = "start_time_ms"
                type        = "integer"
                description = "Epoch timestamp in milliseconds for start"
                required    = false
              }

              property {
                name        = "end_time_ms"
                type        = "integer"
                description = "Epoch timestamp in milliseconds for end"
                required    = false
              }
            }
          }

          # Change Events
          inline_payload {
            name        = "list_change_events"
            description = "Retrieves a history of change events (deployments, configurations) from New Relic for an entity"

            input_schema {
              type = "object"

              property {
                name        = "entity_guid"
                type        = "string"
                description = "The unique identifier for the entity"
                required    = true
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    aws_lambda_function.newrelic_mcp,
    aws_bedrockagentcore_gateway.main
  ]
}
