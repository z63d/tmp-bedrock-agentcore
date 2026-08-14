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
  default     = "product-workload"
}

variable "admin_role_arn" {
  description = "ARN of the IAM role for EKS cluster admin access"
  type        = string
}

variable "agentcore_runtime_role_arn" {
  description = "ARN of the AgentCore Runtime IAM role (for EKS read-only access)"
  type        = string
}
