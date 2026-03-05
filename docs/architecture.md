# アーキテクチャ概要

## システム構成図

```
┌──────────────────────────────────────────────────────────────────────────┐
│                              ユーザー                                      │
└───────────────────────────────┬──────────────────────────────────────────┘
                                │
                                ▼
┌──────────────────────────────────────────────────────────────────────────┐
│                     AgentCore Runtime (ECS/Fargate)                       │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │                         main.ts                                     │  │
│  │  ┌─────────────────────┐    ┌─────────────────────────────────┐   │  │
│  │  │  Strands Agent      │    │  CloudWatch Responses Client    │   │  │
│  │  │  (Calculator等)     │    │  (Bedrock Converse API)         │   │  │
│  │  └─────────────────────┘    └───────────────┬─────────────────┘   │  │
│  └─────────────────────────────────────────────┼─────────────────────┘  │
└────────────────────────────────────────────────┼────────────────────────┘
                                                 │
           ┌─────────────────────────────────────┼─────────────────────────┐
           │                                     │                         │
           ▼                                     ▼                         ▼
┌─────────────────────┐             ┌─────────────────────────┐   ┌──────────────┐
│  AgentCore Memory   │             │  AgentCore Gateway      │   │  Bedrock     │
│  (セマンティック検索)  │             │  (MCP Protocol)         │   │  Foundation  │
└─────────────────────┘             └───────────┬─────────────┘   │  Model       │
                                                │                 └──────────────┘
                                                ▼
                                    ┌─────────────────────────┐
                                    │  API Gateway (IAM認証)   │
                                    └───────────┬─────────────┘
                                                │
                                                ▼
                                    ┌─────────────────────────┐
                                    │  Lambda (Python 3.12)   │
                                    │  CloudWatch MCP Server  │
                                    └───────────┬─────────────┘
                                                │
                        ┌───────────────────────┼───────────────────────┐
                        ▼                       ▼                       ▼
              ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
              │  CloudWatch     │    │  CloudWatch     │    │  CloudWatch     │
              │  Metrics        │    │  Alarms         │    │  Logs           │
              └─────────────────┘    └─────────────────┘    └─────────────────┘
```

## コンポーネント説明

### 1. AgentCore Runtime

メインのエージェントアプリケーション。TypeScript/Node.jsで実装。

**主要機能**:
- ユーザーリクエストの受信・処理
- クエリ内容に基づくルーティング（標準Agent or CloudWatch Agent）
- AgentCore Memoryとの統合（会話履歴・セマンティック検索）

**環境変数**:
| 変数名 | 説明 |
|--------|------|
| `AWS_REGION` | AWSリージョン |
| `BEDROCK_MODEL_ID` | 使用するBedrockモデルID |
| `MEMORY_ID` | AgentCore MemoryのID |
| `GATEWAY_ARN` | AgentCore GatewayのARN |

### 2. CloudWatch MCP Server (Lambda)

CloudWatch APIをMCPプロトコル経由で公開するLambda関数。

**提供ツール**:
| ツール名 | 説明 |
|---------|------|
| `get_metric_data` | メトリクスデータ取得 |
| `analyze_metric` | メトリクス分析（トレンド、統計） |
| `get_active_alarms` | アクティブなアラーム一覧 |
| `get_alarm_history` | アラーム履歴 |
| `describe_log_groups` | ロググループ一覧 |
| `analyze_log_group` | ログ分析（エラーパターン） |
| `execute_log_insights_query` | Logs Insightsクエリ実行 |

### 3. AgentCore Gateway

AgentCore Runtimeとの間でMCPプロトコルを中継するマネージドサービス。

**特徴**:
- IAM認証によるセキュアなアクセス
- ツール自動検出・同期
- 複数ターゲットの統合管理

### 4. API Gateway

Lambda関数へのHTTPエンドポイントを提供。

**設定**:
- REST API (Regional)
- IAM認証 (`AWS_IAM`)
- `/mcp` エンドポイント (POST)

## データフロー

### CloudWatchクエリのフロー

```
1. ユーザー → "過去1時間のEC2 CPU使用率を分析して"
2. main.ts → isCloudWatchRelatedPrompt() でルーティング判定
3. CloudWatchResponsesClient → Bedrock Converse API呼び出し
4. Bedrock → ツール使用を決定 (analyze_metric)
5. CloudWatchResponsesClient → Gateway経由でツール実行
6. Gateway → API Gateway → Lambda
7. Lambda → CloudWatch GetMetricData API
8. 結果が逆順に返却
9. Bedrock → 分析結果をテキスト化
10. ユーザー ← "CPU使用率は平均45%で安定しています..."
```

## インフラストラクチャ

### Terraformリソース

| リソース | ファイル | 説明 |
|---------|---------|------|
| ECR Repository | `cloudwatch-mcp.tf` | Lambda用コンテナイメージ |
| Lambda Function | `cloudwatch-mcp.tf` | CloudWatch MCP Server |
| API Gateway | `cloudwatch-mcp.tf` | REST API + IAM認証 |
| AgentCore Gateway | `gateway.tf` | MCPゲートウェイ |
| Gateway Target | `gateway.tf` | Lambda連携設定 |
| IAM Roles | `main.tf`, `cloudwatch-mcp.tf`, `gateway.tf` | 各コンポーネントの権限 |

### 必要なIAM権限

**CloudWatch MCP Lambda**:
- `cloudwatch:DescribeAlarms`
- `cloudwatch:DescribeAlarmHistory`
- `cloudwatch:GetMetricData`
- `cloudwatch:ListMetrics`
- `logs:DescribeLogGroups`
- `logs:StartQuery`
- `logs:GetQueryResults`
- `logs:StopQuery`

**AgentCore Runtime**:
- `bedrock-agentcore:InvokeGateway`
- `bedrock:InvokeModel`
- 既存のMemory権限

**AgentCore Gateway**:
- `execute-api:Invoke` (API Gateway)
- `lambda:InvokeFunction` (CloudWatch MCP Lambda)
