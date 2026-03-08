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

#------------------------------------------------------------------------------
# CloudWatch MCP Server Variables
#------------------------------------------------------------------------------

variable "cloudwatch_mcp_lambda_memory" {
  description = "Memory size for CloudWatch MCP Lambda in MB"
  type        = number
  default     = 512
}

variable "cloudwatch_mcp_lambda_timeout" {
  description = "Timeout for CloudWatch MCP Lambda in seconds"
  type        = number
  default     = 30
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

variable "newrelic_mcp_lambda_memory" {
  description = "Memory size for New Relic MCP Lambda in MB"
  type        = number
  default     = 512
}

variable "newrelic_mcp_lambda_timeout" {
  description = "Timeout for New Relic MCP Lambda in seconds"
  type        = number
  default     = 60
}

variable "newrelic_api_key" {
  description = "New Relic API key (NRAK-xxxxx)"
  type        = string
  sensitive   = true
}

variable "newrelic_mcp_region" {
  description = "New Relic region (us or eu)"
  type        = string
  default     = "us"

  validation {
    condition     = contains(["us", "eu"], var.newrelic_mcp_region)
    error_message = "newrelic_mcp_region must be 'us' or 'eu'"
  }
}

variable "newrelic_default_account_id" {
  description = "Default New Relic account ID to use when not specified in tool calls"
  type        = string
  default     = ""
}
