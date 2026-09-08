# Observability

AgentCore Runtime のログとトレースの仕組みをまとめる。

## ログの種類

AgentCore Runtime は 2 種類のログを出力する:

| ログ                           | Log Stream                                | 内容                                                               | 発生元                                            |
| ------------------------------ | ----------------------------------------- | ------------------------------------------------------------------ | ------------------------------------------------- |
| **アプリケーションログ**       | `[runtime-logs]...`                       | `logger.info()` 等のアプリコードの出力                             | コンテナ stdout（structlog）                      |
| **プラットフォームテレメトリ** | `BedrockAgentCoreRuntime_ApplicationLogs` | リクエスト/レスポンスの構造化ログ（trace_id, span_id, payload 等） | AgentCore Runtime プラットフォーム（Vended Logs） |

### アプリケーションログ（runtime-logs）

コンテナの stdout に出力されたログが自動的に CloudWatch Logs に配信される。設定不要。

- Log Group: `/aws/bedrock-agentcore/runtimes/{runtime_id}-DEFAULT`（自動作成）
- Log Stream: `[runtime-logs]{session-uuid}`
- フォーマット: structlog の JSON 出力

### プラットフォームテレメトリ（Vended Logs）

AgentCore Runtime プラットフォームが生成する構造化テレメトリ。`aws_cloudwatch_log_delivery` リソースで配信先を設定する。

- Log Group: Terraform で管理（retention 等を制御するため）
- Log Stream: `BedrockAgentCoreRuntime_ApplicationLogs`

設定しない場合、このテレメトリは出力されない。

```json
{
  "trace_id": "6a9ea46f...",
  "span_id": "0ae3ef35...",
  "session_id": "slack-C097QCS63C5-...",
  "operation": "InvokeAgentRuntime",
  "body": {
    "request_payload": { "prompt": "...", "sessionId": "..." },
    "response_payload": null
  }
}
```

用途:

- trace_id / span_id によるリクエストの追跡
- リクエストペイロードの監査
- CloudWatch GenAI Observability ダッシュボードとの連携

### Vended Logs の Terraform 設定

3 つのリソースで「どこから」「どこに」配信するかを定義する:

```hcl
# ログの発生元（= AgentCore Runtime）
resource "aws_cloudwatch_log_delivery_source" "agentcore_runtime" {
  name         = "agentcore-runtime"
  log_type     = "APPLICATION_LOGS"
  resource_arn = aws_bedrockagentcore_agent_runtime.main.agent_runtime_arn
}

# ログの送信先（= CloudWatch Log Group）
resource "aws_cloudwatch_log_delivery_destination" "agentcore_runtime" {
  name = "agentcore-runtime"
  delivery_destination_configuration {
    destination_resource_arn = aws_cloudwatch_log_group.agentcore_runtime.arn
  }
}

# 発生元と送信先を紐づけて配信を有効化
resource "aws_cloudwatch_log_delivery" "agentcore_runtime" {
  delivery_source_name     = aws_cloudwatch_log_delivery_source.agentcore_runtime.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.agentcore_runtime.arn
}
```

Gateway にも同じ 3 リソースが必要（Gateway も Vended Logs でテレメトリを出力するため）。

## 参考

- [AgentCore Observability - Configure](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/observability-configure.html)
- [AgentCore Observability - Get Started](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/observability-get-started.html)
