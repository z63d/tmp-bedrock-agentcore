# アーキテクチャ

## システム構成図

```
ユーザー / CLI
      │  InvokeAgentRuntime (SigV4)
      ▼
┌─────────────────────────────────────────┐
│  AgentCore Runtime (ECS/Fargate, arm64)  │
│  app-py — Python 3.13 / Strands Agents   │
│                                          │
│  BedrockModel (claude-3-haiku 等)        │
│  MCPClient → Gateway                    │
│  MemoryClient → Memory API              │
└──────┬───────────────────┬───────────────┘
       │ Memory API        │ InvokeGateway (SigV4)
       ▼                   ▼
┌──────────────┐   ┌──────────────────────┐
│ AgentCore    │   │ AgentCore Gateway     │
│ Memory       │   │ (MCP Protocol / IAM)  │
│ (Semantic)   │   └──────┬───────────────┘
└──────────────┘          │ Lambda 直接呼び出し
                          ▼
        ┌─────────────────┬─────────────────┐
        ▼                 ▼                 ▼
  ┌───────────┐    ┌───────────┐    ┌───────────┐
  │CloudWatch │    │  Rollbar  │    │ New Relic │
  │MCP(Lambda)│    │MCP(Lambda)│    │MCP(Lambda)│
  └─────┬─────┘    └─────┬─────┘    └─────┬─────┘
        ▼                ▼                 ▼
  CloudWatch       Rollbar API       New Relic API
  (Logs/Metrics
   /Alarms)
```

## コンポーネント

### AgentCore Runtime (`app-py/`)

**役割**: ユーザーリクエストを受け取り、Strands Agent が Bedrock モデルと MCP ツールを使って回答する。

- `BedrockAgentCoreApp` が `/invocations` (エージェント呼び出し) と `/ping` (ヘルスチェック) エンドポイントを提供
- 起動時に `MEMORY_ID` / `GATEWAY_ID` が未設定なら Memory / MCP を無効化して動作する
- レスポンスは SSE (Server-Sent Events) 形式で返す
- OpenTelemetry (`aws-opentelemetry-distro`) によるトレース付き

**主な環境変数**:

| 変数               | 既定                    | 説明                                      |
| ------------------ | ----------------------- | ----------------------------------------- |
| `AWS_REGION`       | `ap-northeast-1`        | AWS リージョン                            |
| `BEDROCK_MODEL_ID` | `amazon.nova-lite-v1:0` | Bedrock モデル ID（Terraform 側で上書き） |
| `MEMORY_ID`        | —                       | AgentCore Memory の ID（未設定で無効）    |
| `GATEWAY_ID`       | —                       | AgentCore Gateway の ID（未設定で無効）   |

### AgentCore Memory

会話ターンを `CreateEvent` で保存し、`RetrieveMemoryRecords` でベクトル類似検索する。
Memory Strategy は `SEMANTIC` タイプを使用。イベントの保持期間は 30 日。

リクエスト処理フロー:

1. `RetrieveMemoryRecords` で過去の関連会話を取得 (top_k=3)
2. 取得できた場合は `[Previous context]` として現在のプロンプトと結合
3. Agent 実行後、会話ターンを `CreateEvent` で保存

### AgentCore Gateway

AgentCore Runtime と MCP サーバー（Lambda）の間を中継するマネージドサービス。

- IAM 認証（SigV4）でセキュアに Runtime から呼び出す
- Lambda を MCP ターゲットとして登録し、ツールを自動検出・同期する
- Runtime 側は `mcp-proxy-for-aws` の `aws_iam_streamablehttp_client` で接続

### MCP サーバー群（Lambda, arm64）

| Lambda           | 言語       | 主なツール                                             |
| ---------------- | ---------- | ------------------------------------------------------ |
| `cloudwatch-mcp` | Python     | CloudWatch Logs/Metrics/Alarms の取得・分析            |
| `rollbar-mcp`    | TypeScript | エラーアイテム一覧、詳細、デプロイ履歴、ステータス更新 |
| `newrelic-mcp`   | TypeScript | NRQL クエリ実行、エンティティ検索、アラート取得        |

## データフロー（インシデント調査の例）

```
1. ユーザー → "過去1時間の 5xx エラーを分析して"

2. Runtime: Memory を検索（関連する過去会話があれば context に追加）

3. Strands Agent → Bedrock モデル呼び出し
   モデルが get_active_alarms / analyze_log_group 等を選択

4. Runtime → Gateway (InvokeGateway, SigV4)
   Gateway → cloudwatch-mcp Lambda → CloudWatch API

5. 結果を受け取り、モデルが自然言語で分析結果を生成

6. Runtime → ユーザーへ SSE レスポンス

7. Runtime: 会話ターンを Memory に保存（CreateEvent）
```

## インフラ（Terraform リソース一覧）

| リソース                      | ファイル                       | 説明                     |
| ----------------------------- | ------------------------------ | ------------------------ |
| ECR Repository (agent)        | `bedrock-agentcore-runtime.tf` | Runtime コンテナイメージ |
| IAM Role (agentcore-runtime)  | `bedrock-agentcore-runtime.tf` | Runtime 実行ロール       |
| AgentCore Runtime             | `bedrock-agentcore-runtime.tf` | エージェント実行環境     |
| CloudWatch Log Group          | `bedrock-agentcore-runtime.tf` | Runtime ログ             |
| AgentCore Memory              | `bedrock-agentcore-memory.tf`  | セマンティック記憶       |
| AgentCore Gateway             | `bedrock-agentcore-gateway.tf` | MCP Gateway              |
| ECR + Lambda (cloudwatch-mcp) | `cloudwatch-mcp-server.tf`     | CloudWatch MCP           |
| ECR + Lambda (rollbar-mcp)    | `rollbar-mcp-server.tf`        | Rollbar MCP              |
| ECR + Lambda (newrelic-mcp)   | `newrelic-mcp-server.tf`       | New Relic MCP            |

## IAM 権限

### AgentCore Runtime ロール

- `bedrock:InvokeModel` / `bedrock:InvokeModelWithResponseStream` — モデル呼び出し
- `ecr:GetAuthorizationToken` / `BatchGetImage` / `GetDownloadUrlForLayer` — ECR アクセス
- `logs:CreateLogGroup` / `CreateLogStream` / `PutLogEvents` — CloudWatch Logs
- `xray:PutTraceSegments` 等 — X-Ray トレーシング
- `bedrock-agentcore:CreateEvent` / `RetrieveMemoryRecords` 等 — Memory API
- `bedrock-agentcore:InvokeGateway` — Gateway 呼び出し

### CloudWatch MCP Lambda ロール

- `cloudwatch:DescribeAlarms` / `DescribeAlarmHistory` / `GetMetricData` / `ListMetrics`
- `logs:DescribeLogGroups` / `StartQuery` / `GetQueryResults` / `StopQuery`
</content>

</invoke>
