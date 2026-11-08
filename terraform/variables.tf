locals {
  account_id = data.aws_caller_identity.current.account_id
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"
}

variable "aws_profile" {
  description = "AWS CLI profile name"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
  default     = "k-bedrock-agentcore"
}

variable "eks_cluster_name" {
  description = "EKS cluster name for K8s tools (empty = disabled)"
  type        = string
  default     = "product-workload"
}

variable "mysql_secret_arn" {
  description = "Secrets Manager ARN for MySQL credentials (empty = disabled). Secret must contain: username, password, host, port, dbname"
  type        = string
  default     = ""
}

#------------------------------------------------------------------------------
# Feature Toggles
#------------------------------------------------------------------------------

variable "enable_rollbar_mcp" {
  type    = bool
  default = false
}

variable "enable_newrelic_mcp" {
  type    = bool
  default = false
}

variable "enable_aws_mcp" {
  type    = bool
  default = false
}

variable "enable_github_mcp" {
  type    = bool
  default = true
}

variable "enable_slack_mcp" {
  type    = bool
  default = false
}

variable "enable_slack_ext_mcp" {
  type    = bool
  default = false
}

variable "enable_google_workspace_mcp" {
  type    = bool
  default = false
}

variable "enable_vpc_peering" {
  description = "Create VPC Peering to product-workload VPC"
  type        = bool
  default     = false
}

#------------------------------------------------------------------------------
# Rollbar MCP Server Variables
#------------------------------------------------------------------------------

variable "rollbar_mcp_lambda_memory" {
  description = "Memory size for Rollbar MCP Lambda in MB"
  type        = number
  default     = 512
}

variable "rollbar_mcp_lambda_timeout" {
  description = "Timeout for Rollbar MCP Lambda in seconds"
  type        = number
  default     = 30
}

variable "rollbar_access_token" {
  description = "Rollbar API access token (sensitive)"
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = !var.enable_rollbar_mcp || var.rollbar_access_token != null
    error_message = "rollbar_access_token is required when enable_rollbar_mcp = true."
  }
}

#------------------------------------------------------------------------------
# New Relic MCP Server Variables
#------------------------------------------------------------------------------

variable "newrelic_api_key" {
  description = "New Relic API key (NRAK-xxxxx). Used for Gateway outbound auth to the official New Relic MCP server."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = !var.enable_newrelic_mcp || var.newrelic_api_key != null
    error_message = "newrelic_api_key is required when enable_newrelic_mcp = true."
  }
}

#------------------------------------------------------------------------------
# GitHub MCP Server Variables
#------------------------------------------------------------------------------

variable "github_pat" {
  description = "GitHub PAT (e.g. 'ghp_xxxxx'). 'Bearer ' prefix is added automatically. Used for Gateway outbound auth to the official GitHub MCP server."
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition     = !var.enable_github_mcp || var.github_pat != null
    error_message = "github_pat is required when enable_github_mcp = true."
  }
}

#------------------------------------------------------------------------------
# Slack Bot Variables
#------------------------------------------------------------------------------

variable "slack_bot_token" {
  description = "Slack Bot User OAuth Token (xoxb-xxxxx)"
  type        = string
  sensitive   = true
}

variable "slack_signing_secret" {
  description = "Slack App Signing Secret"
  type        = string
  sensitive   = true
}

variable "allowed_slack_channel_ids" {
  description = "Slack channel IDs allowed to use the bot. Empty = all channels allowed."
  type        = list(string)
  default     = []
}

variable "allowed_slack_user_ids" {
  description = "Slack user IDs allowed to use the bot. Empty = all users allowed."
  type        = list(string)
  default     = []
}

#------------------------------------------------------------------------------
# Google Workspace MCP Server Variables
#------------------------------------------------------------------------------

variable "google_cloud_service_account_key_path" {
  description = "Path to Google Cloud Service Account key JSON file for Google Workspace MCP. TODO: Migrate to Workload Identity Federation."
  type        = string
  default     = null

  validation {
    condition     = !var.enable_google_workspace_mcp || var.google_cloud_service_account_key_path != null
    error_message = "google_cloud_service_account_key_path is required when enable_google_workspace_mcp = true."
  }
}

variable "google_workspace_mcp_lambda_memory" {
  description = "Memory size for Google Workspace MCP Lambda in MB"
  type        = number
  default     = 512
}

variable "google_workspace_mcp_lambda_timeout" {
  description = "Timeout for Google Workspace MCP Lambda in seconds"
  type        = number
  default     = 60
}
