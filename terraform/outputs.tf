output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = aws_ecr_repository.agent.repository_url
}

output "agent_runtime_arn" {
  description = "ARN of the AgentCore Runtime"
  value       = aws_bedrockagentcore_agent_runtime.main.agent_runtime_arn
}

output "agent_runtime_id" {
  description = "ID of the AgentCore Runtime"
  value       = aws_bedrockagentcore_agent_runtime.main.agent_runtime_id
}

output "agent_runtime_name" {
  description = "Name of the AgentCore Runtime"
  value       = aws_bedrockagentcore_agent_runtime.main.agent_runtime_name
}

output "agentcore_role_arn" {
  description = "ARN of the AgentCore Runtime IAM role"
  value       = aws_iam_role.agentcore_runtime.arn
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "memory_id" {
  description = "ID of the AgentCore Memory"
  value       = aws_bedrockagentcore_memory.main.id
}

output "memory_arn" {
  description = "ARN of the AgentCore Memory"
  value       = aws_bedrockagentcore_memory.main.arn
}


output "gateway_id" {
  description = "ID of the AgentCore Gateway"
  value       = aws_bedrockagentcore_gateway.main.gateway_id
}

output "gateway_arn" {
  description = "ARN of the AgentCore Gateway"
  value       = aws_bedrockagentcore_gateway.main.gateway_arn
}

#------------------------------------------------------------------------------
# Rollbar MCP Server Outputs
#------------------------------------------------------------------------------

output "rollbar_mcp_ecr_repository_url" {
  description = "URL of the Rollbar MCP ECR repository"
  value       = aws_ecr_repository.rollbar_mcp.repository_url
}

output "rollbar_mcp_lambda_arn" {
  description = "ARN of the Rollbar MCP Lambda function"
  value       = aws_lambda_function.rollbar_mcp.arn
}
