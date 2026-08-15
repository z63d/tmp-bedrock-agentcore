#------------------------------------------------------------------------------
# AgentCore Memory
#------------------------------------------------------------------------------

resource "aws_bedrockagentcore_memory" "main" {
  name                  = replace(var.project_name, "-", "_")
  description           = "Memory for ${var.project_name} agent"
  event_expiry_duration = 7
}

resource "aws_bedrockagentcore_memory_strategy" "semantic" {
  name                = "semantic_memory"
  memory_id           = aws_bedrockagentcore_memory.main.id
  type                = "SEMANTIC"
  namespace_templates = ["/strategies/{memoryStrategyId}/actors/{actorId}/"]
}
