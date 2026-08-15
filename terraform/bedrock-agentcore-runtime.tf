#------------------------------------------------------------------------------
# ECR Repository
#------------------------------------------------------------------------------

resource "aws_ecr_repository" "agent" {
  name                 = "${var.project_name}-agent"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "agent" {
  repository = aws_ecr_repository.agent.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
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
        Resource = [
          "arn:aws:bedrock:*::foundation-model/*",
          "arn:aws:bedrock:*::inference-profile/*",
          "arn:aws:bedrock:*:${local.account_id}:inference-profile/*"
        ]
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
        Sid    = "EKSDescribeCluster"
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster"
        ]
        Resource = "arn:aws:eks:${var.aws_region}:${local.account_id}:cluster/*"
      },
      {
        Sid    = "RDSSecretAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = "arn:aws:secretsmanager:${var.aws_region}:${local.account_id}:secret:product-workload/rds-mysql-agentcore-runtime-*"
      },
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
    network_mode = "VPC"

    network_mode_config {
      subnets         = [aws_subnet.private.id]
      security_groups = [aws_security_group.agentcore_runtime.id]
    }
  }

  environment_variables = {
    AWS_REGION       = var.aws_region
    BEDROCK_MODEL_ID = "jp.anthropic.claude-haiku-4-5-20251001-v1:0"
    MEMORY_ID        = aws_bedrockagentcore_memory.main.id
    GATEWAY_ID       = aws_bedrockagentcore_gateway.main.gateway_id
    EKS_CLUSTER_NAME = var.eks_cluster_name
    MYSQL_SECRET_ARN = var.mysql_secret_arn
    PYTHONUNBUFFERED = "1"
  }

  lifecycle_configuration {
    idle_runtime_session_timeout = 600
    max_lifetime                 = 1800
  }

  protocol_configuration {
    server_protocol = "HTTP"
  }

  depends_on = [aws_bedrockagentcore_memory_strategy.semantic]
}

#------------------------------------------------------------------------------
# CloudWatch Logs for AgentCore Runtime
#------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "agentcore_runtime" {
  name              = "/aws/bedrock-agentcore/runtimes/${aws_bedrockagentcore_agent_runtime.main.agent_runtime_id}-DEFAULT"
  retention_in_days = 3
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
