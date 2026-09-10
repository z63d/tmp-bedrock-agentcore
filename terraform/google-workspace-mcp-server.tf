#------------------------------------------------------------------------------
# Google Workspace MCP Server - Docker Lambda + Function URL
#
# Runs piotr-agier/google-drive-mcp as a Streamable HTTP server
# on Lambda via Lambda Web Adapter. Gateway connects as mcp_server target.
#
# Auth: Google Cloud Service Account key (stored in Secrets Manager)
# TODO: Migrate to Workload Identity Federation (see wif-credential-config.json.example)
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# ECR Repository
#------------------------------------------------------------------------------

resource "aws_ecr_repository" "google_workspace_mcp" {
  name                 = "${var.project_name}-google-workspace-mcp"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "google_workspace_mcp" {
  repository = aws_ecr_repository.google_workspace_mcp.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = {
        type = "expire"
      }
    }]
  })
}

#------------------------------------------------------------------------------
# Secrets Manager - Google Cloud Service Account Key
#------------------------------------------------------------------------------

locals {
  google_cloud_sa_key_json = file(var.google_cloud_service_account_key_path)
}

resource "aws_secretsmanager_secret" "google_cloud_sa_key" {
  name                    = "${var.project_name}/google-cloud-sa-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "google_cloud_sa_key" {
  secret_id     = aws_secretsmanager_secret.google_cloud_sa_key.id
  secret_string = local.google_cloud_sa_key_json
}

#------------------------------------------------------------------------------
# IAM Role for Lambda
#------------------------------------------------------------------------------

resource "aws_iam_role" "google_workspace_mcp_lambda" {
  name = "${var.project_name}-google-workspace-mcp-lambda"

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

resource "aws_iam_role_policy" "google_workspace_mcp_lambda" {
  name = "${var.project_name}-google-workspace-mcp-policy"
  role = aws_iam_role.google_workspace_mcp_lambda.id

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
        Resource = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:/aws/lambda/${var.project_name}-google-workspace-mcp:*"
      },
      {
        Sid    = "GetGoogleCloudServiceAccountKey"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = aws_secretsmanager_secret.google_cloud_sa_key.arn
      }
    ]
  })
}

#------------------------------------------------------------------------------
# Lambda Function (Docker image via ECR)
#------------------------------------------------------------------------------

resource "aws_lambda_function" "google_workspace_mcp" {
  function_name = "${var.project_name}-google-workspace-mcp"
  role          = aws_iam_role.google_workspace_mcp_lambda.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.google_workspace_mcp.repository_url}:latest"
  architectures = ["arm64"]
  memory_size   = var.google_workspace_mcp_lambda_memory
  timeout       = var.google_workspace_mcp_lambda_timeout

  environment {
    variables = {
      GOOGLE_CLOUD_SA_KEY_JSON = aws_secretsmanager_secret_version.google_cloud_sa_key.secret_string
    }
  }

  depends_on = [aws_iam_role_policy.google_workspace_mcp_lambda]
}

#------------------------------------------------------------------------------
# Lambda Function URL (IAM auth)
#------------------------------------------------------------------------------

resource "aws_lambda_function_url" "google_workspace_mcp" {
  function_name      = aws_lambda_function.google_workspace_mcp.function_name
  authorization_type = "AWS_IAM"
  invoke_mode        = "RESPONSE_STREAM"
}

resource "aws_lambda_permission" "google_workspace_mcp_function_url" {
  statement_id           = "AllowGatewayFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.google_workspace_mcp.function_name
  principal              = aws_iam_role.gateway.arn
  function_url_auth_type = "AWS_IAM"
}

#------------------------------------------------------------------------------
# CloudWatch Logs
#------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "google_workspace_mcp" {
  name              = "/aws/lambda/${var.project_name}-google-workspace-mcp"
  retention_in_days = 3
}

# Gateway Target is defined in bedrock-agentcore-gateway.tf

#------------------------------------------------------------------------------
# TODO: Workload Identity Federation (replace SA key)
#
# 1. Google Cloud: Create WIF Pool + Provider + Service Account
# 2. Generate credential config:
#    gcloud iam workload-identity-pools create-cred-config \
#      projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/POOL_ID/providers/PROVIDER_ID \
#      --service-account=SA@PROJECT.iam.gserviceaccount.com \
#      --aws \
#      --output-file=apps/lambda-google-workspace-mcp/wif-credential-config.json
# 3. Bake into Docker image (no secrets in the file)
# 4. Remove Secrets Manager resources and env var
# 5. Set GOOGLE_APPLICATION_CREDENTIALS=/app/wif-credential-config.json
#------------------------------------------------------------------------------
