#------------------------------------------------------------------------------
# AgentCore Policy Engine + Cedar Policies
#
# Restricts Slack MCP tool access to specific channels via Cedar policies.
# Policy Engine evaluates all tool calls at the Gateway layer (<1ms).
#
# Mode starts as LOG_ONLY for safe rollout. Switch to ENFORCE after
# verifying in CloudWatch Logs that the correct calls are being permitted/denied.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Policy Engine
#------------------------------------------------------------------------------

resource "aws_bedrockagentcore_policy_engine" "main" {
  name = replace("${var.project_name}_policy", "-", "_")
}


#------------------------------------------------------------------------------
# Baseline: permit all actions
#------------------------------------------------------------------------------

locals {
  gateway_resource    = "AgentCore::Gateway::\"${aws_bedrockagentcore_gateway.main.gateway_arn}\""
  slack_target_name   = aws_bedrockagentcore_gateway_target.slack_mcp.name
  allowed_channel_set = join(", ", formatlist("\"%s\"", var.allowed_slack_channel_ids))
}

resource "aws_bedrockagentcore_policy" "default_permit" {
  name             = "default_permit"
  policy_engine_id = aws_bedrockagentcore_policy_engine.main.policy_engine_id
  description      = "Baseline permit-all policy (forbid policies override this for restricted tools)"
  # Intentionally broad: forbid policies restrict specific tools.
  # Skip "Overly Permissive" automated reasoning finding.
  validation_mode = "IGNORE_ALL_FINDINGS"

  definition {
    cedar {
      statement = "permit(principal, action, resource == ${local.gateway_resource});"
    }
  }
}

#------------------------------------------------------------------------------
# Slack channel restriction: forbid message reading outside the allowlist
#
# Action format: AgentCore::Action::"<target_name>___<tool>"
#
# conversations_history / conversations_replies:
#   Have a `channel_id` input parameter → restrict to allowlist
#
# conversations_search_messages / conversations_unreads:
#   Not registered as gateway actions (remote MCP, listing_mode=DEFAULT).
#   Cannot create Cedar policies for unrecognized actions.
#------------------------------------------------------------------------------

# Restrict conversations_history to allowed channels
resource "aws_bedrockagentcore_policy" "forbid_conversations_history" {
  count            = length(var.allowed_slack_channel_ids) > 0 ? 1 : 0
  name             = "forbid_conversations_history"
  policy_engine_id = aws_bedrockagentcore_policy_engine.main.policy_engine_id
  description      = "Restrict channel history to allowed channels only"

  definition {
    cedar {
      statement = <<-EOT
        forbid(
          principal,
          action == AgentCore::Action::"${local.slack_target_name}___conversations_history",
          resource == ${local.gateway_resource}
        ) unless {
          [${local.allowed_channel_set}].contains(context.input.channel_id)
        };
      EOT
    }
  }
}

# Restrict conversations_replies to allowed channels
resource "aws_bedrockagentcore_policy" "forbid_conversations_replies" {
  count            = length(var.allowed_slack_channel_ids) > 0 ? 1 : 0
  name             = "forbid_conversations_replies"
  policy_engine_id = aws_bedrockagentcore_policy_engine.main.policy_engine_id
  description      = "Restrict thread replies to allowed channels only"

  definition {
    cedar {
      statement = <<-EOT
        forbid(
          principal,
          action == AgentCore::Action::"${local.slack_target_name}___conversations_replies",
          resource == ${local.gateway_resource}
        ) unless {
          [${local.allowed_channel_set}].contains(context.input.channel_id)
        };
      EOT
    }
  }
}

