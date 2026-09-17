#------------------------------------------------------------------------------
# GitHub MCP Server
#
# 公式リモート MCP サーバー (https://api.githubcopilot.com/mcp/) を Gateway の
# MCP Server Target として利用する。
# ここでは Gateway のアウトバウンド認証用 credential provider のみ定義する。
# (Gateway Target 本体は bedrock-agentcore-gateway.tf を参照)
#------------------------------------------------------------------------------

resource "aws_bedrockagentcore_api_key_credential_provider" "github" {
  name               = "github-pat"
  api_key_wo         = "Bearer ${var.github_pat}"
  api_key_wo_version = 1
}
