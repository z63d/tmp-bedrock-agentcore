#------------------------------------------------------------------------------
# New Relic MCP Server
#
# 公式 MCP サーバー (https://mcp.newrelic.com/mcp/) を Gateway の
# MCP Server Target として利用する。
# ここでは Gateway のアウトバウンド認証用 API キーのみ定義する。
# (Gateway Target 本体は bedrock-agentcore-gateway.tf を参照)
#------------------------------------------------------------------------------

resource "aws_bedrockagentcore_api_key_credential_provider" "newrelic" {
  name               = "newrelic-api-key"
  api_key_wo         = var.newrelic_api_key
  api_key_wo_version = 1
}
