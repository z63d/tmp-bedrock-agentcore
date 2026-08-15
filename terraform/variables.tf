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
}

#------------------------------------------------------------------------------
# New Relic MCP Server Variables
#------------------------------------------------------------------------------

variable "newrelic_api_key" {
  description = "New Relic API key (NRAK-xxxxx). Used for Gateway outbound auth to the official New Relic MCP server."
  type        = string
  sensitive   = true
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

variable "slack_bot_lambda_memory" {
  description = "Memory size for Slack Bot Lambda in MB"
  type        = number
  default     = 256
}

variable "slack_bot_lambda_timeout" {
  description = "Timeout for Slack Bot Lambda in seconds"
  type        = number
  default     = 120
}
