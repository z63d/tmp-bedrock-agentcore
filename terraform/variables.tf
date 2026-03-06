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
