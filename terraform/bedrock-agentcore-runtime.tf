locals {
  account_id = data.aws_caller_identity.current.account_id
}

#------------------------------------------------------------------------------
# ECR Repository
#------------------------------------------------------------------------------

resource "aws_ecr_repository" "agent" {
  name                 = "${var.project_name}-agent"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }
}

#------------------------------------------------------------------------------
# IAM Role for AgentCore Runtime
#------------------------------------------------------------------------------

resource "aws_iam_role" "agentcore_runtime" {
  name = "${var.project_name}-agentcore-runtime"

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
          ArnLike = {
            "aws:SourceArn" = "arn:aws:bedrock-agentcore:${var.aws_region}:${local.account_id}:*"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "agentcore_runtime" {
  name = "${var.project_name}-agentcore-runtime"
  role = aws_iam_role.agentcore_runtime.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BedrockModelInvocation"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/*"
      },
      {
        Sid    = "ECRAccess"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = "*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${local.account_id}:*"
      },
      {
        Sid    = "XRayTracing"
        Effect = "Allow"
        Action = [
          "xray:PutTraceSegments",
          "xray:PutTelemetryRecords",
          "xray:GetSamplingRules",
          "xray:GetSamplingTargets"
        ]
        Resource = "*"
      },
      {
        Sid    = "AgentCoreMemory"
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:CreateSession",
          "bedrock-agentcore:GetSession",
          "bedrock-agentcore:ListSessions",
          "bedrock-agentcore:DeleteSession",
          "bedrock-agentcore:CreateEvent",
          "bedrock-agentcore:ListEvents",
          "bedrock-agentcore:RetrieveMemoryRecords",
          "bedrock-agentcore:IngestMemoryRecords",
          "bedrock-agentcore:ListMemoryRecords"
        ]
        Resource = "arn:aws:bedrock-agentcore:${var.aws_region}:${local.account_id}:memory/*"
      },
      {
        Sid    = "AgentCoreGateway"
        Effect = "Allow"
        Action = [
          "bedrock-agentcore:InvokeGateway"
        ]
        Resource = aws_bedrockagentcore_gateway.main.gateway_arn
      },
      {
        Sid    = "BedrockResponsesAPI"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/*"
      }
    ]
  })
}

#------------------------------------------------------------------------------
# AgentCore Runtime
#------------------------------------------------------------------------------

resource "aws_bedrockagentcore_agent_runtime" "main" {
  agent_runtime_name = replace(var.project_name, "-", "_")
  role_arn           = aws_iam_role.agentcore_runtime.arn

  agent_runtime_artifact {
    container_configuration {
      container_uri = "${aws_ecr_repository.agent.repository_url}:latest"
    }
  }

  network_configuration {
    network_mode = "PUBLIC"
  }

  environment_variables = {
    AWS_REGION       = var.aws_region
    BEDROCK_MODEL_ID = "anthropic.claude-3-haiku-20240307-v1:0"
    MEMORY_ID        = aws_bedrockagentcore_memory.main.id
    GATEWAY_ID       = aws_bedrockagentcore_gateway.main.gateway_id
    PYTHONUNBUFFERED = "1"
  }

  depends_on = [aws_bedrockagentcore_memory_strategy.semantic]
}

#------------------------------------------------------------------------------
# CloudWatch Logs for AgentCore Runtime
#------------------------------------------------------------------------------

import {
  to = aws_cloudwatch_log_group.agentcore_runtime
  id = "/aws/bedrock-agentcore/runtimes/${aws_bedrockagentcore_agent_runtime.main.agent_runtime_id}-DEFAULT"
}

resource "aws_cloudwatch_log_group" "agentcore_runtime" {
  name              = "/aws/bedrock-agentcore/runtimes/${aws_bedrockagentcore_agent_runtime.main.agent_runtime_id}-DEFAULT"
  retention_in_days = 30
}

resource "aws_cloudwatch_log_delivery_source" "agentcore_runtime" {
  name         = "${var.project_name}-agentcore-runtime"
  log_type     = "APPLICATION_LOGS"
  resource_arn = aws_bedrockagentcore_agent_runtime.main.agent_runtime_arn
}

resource "aws_cloudwatch_log_delivery_destination" "agentcore_runtime" {
  name = "${var.project_name}-agentcore-runtime"

  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.agentcore_runtime.arn
  }
}

resource "aws_cloudwatch_log_delivery" "agentcore_runtime" {
  delivery_source_name     = aws_cloudwatch_log_delivery_source.agentcore_runtime.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.agentcore_runtime.arn
}
