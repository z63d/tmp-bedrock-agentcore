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
