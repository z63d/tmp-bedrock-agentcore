# アーキテクチャ

## システム構成図

```
ユーザー / CLI / Slack Bot
      │  InvokeAgentRuntime (SigV4)
      ▼
┌──────────────────────────────────────────────────────┐
│  AgentCore Runtime (ECS/Fargate, arm64)               │
│  bedrock-agentcore-sre — Python 3.13 / Strands Agents │
│                                                       │
│  BedrockModel (claude-haiku-4.5 等)                   │
│  MCPClient → Gateway                                 │
│  MemoryClient → Memory API                           │
│  K8s Tools → EKS API (kubernetes client)             │
└───┬──────────┬──────────────────┬────────────────────┘
    │          │                  │
    │ Memory   │ InvokeGateway    │ K8s API (HTTPS)
    ▼          ▼                  │ VPC Peering 経由
┌────────┐ ┌──────────────┐      │
│Memory  │ │ Gateway      │      ▼
│(Seman.)│ │ (MCP / IAM)  │  EKS / RDS (Product VPC)
└────────┘ └──────┬───────┘
          ┌───────┴────────┐
          │ Lambda / MCP   │
          ▼                ▼
   ┌───────────┐  ┌────────────┐
   │ Rollbar   │  │ New Relic  │
   │ MCP       │  │ MCP        │
   │ (Lambda)  │  │ (公式)     │
   └───────────┘  └────────────┘
```

## ネットワーク構成

```
AgentCore VPC (10.1.0.0/16, ap-northeast-1d)
├── public subnet  (10.1.0.0/24)  — NAT Gateway
├── private subnet (10.1.10.0/24) — AgentCore Runtime ENI
├── S3 Gateway Endpoint
└── VPC Peering ──► Product VPC
```

- Runtime は VPC モードで private subnet に ENI を配置（Security Hub `BedrockAgentCore.1` 準拠）
- 外部 API（New Relic MCP 等）は NAT Gateway 経由
- EKS / RDS へは VPC Peering 経由で直接アクセス
- Product VPC の構成は [`product-workload/README.md`](../product-workload/README.md) を参照

## コンポーネント

### AgentCore Runtime (`app/bedrock-agentcore-sre/`)

**役割**: ユーザーリクエストを受け取り、Strands Agent が Bedrock モデルと MCP ツールを使って回答する。

- `BedrockAgentCoreApp` が `/invocations` (エージェント呼び出し) と `/ping` (ヘルスチェック) エンドポイントを提供
- 起動時に `MEMORY_ID` / `GATEWAY_ID` / `EKS_CLUSTER_NAME` が未設定なら各機能を無効化して動作する
- レスポンスは SSE (Server-Sent Events) 形式で返す
- OpenTelemetry (`aws-opentelemetry-distro`) によるトレース付き

**主な環境変数**:

| 変数               | 既定                    | 説明                                        |
| ------------------ | ----------------------- | ------------------------------------------- |
| `AWS_REGION`       | `ap-northeast-1`        | AWS リージョン                              |
| `BEDROCK_MODEL_ID` | `amazon.nova-lite-v1:0` | Bedrock モデル ID（Terraform 側で上書き）   |
| `MEMORY_ID`        | —                       | AgentCore Memory の ID（未設定で無効）      |
| `GATEWAY_ID`       | —                       | AgentCore Gateway の ID（未設定で無効）     |
| `EKS_CLUSTER_NAME` | —                       | EKS クラスター名（未設定で K8s ツール無効） |

### Kubernetes ツール

Runtime に組み込みの Strands Agent ツール。`kubernetes` Python ライブラリで EKS API を直接叩く。

- 認証: STS presigned URL でトークン生成（kubeconfig / kubectl 不要）
- 権限: EKS Access Entry で `AmazonEKSViewPolicy` (read-only) をマッピング
- VPC Peering 経由で EKS API endpoint にアクセス

### AgentCore Memory

会話ターンを `CreateEvent` で保存し、`RetrieveMemoryRecords` でベクトル類似検索する。
Memory Strategy は `SEMANTIC` タイプを使用。イベントの保持期間は 30 日。

リクエスト処理フロー:

1. `RetrieveMemoryRecords` で過去の関連会話を取得 (top_k=3)
2. 取得できた場合は `[Previous context]` として現在のプロンプトと結合
3. Agent 実行後、会話ターンを `CreateEvent` で保存

### AgentCore Gateway

AgentCore Runtime と各種ツールバックエンドの間を中継するマネージドサービス。

- IAM 認証（SigV4）でセキュアに Runtime から呼び出す
- ターゲットは2種類:
  - **Lambda ターゲット**: 自前実装の MCP サーバー Lambda（Rollbar）
  - **MCP Server ターゲット**: 外部の MCP サーバーを直接プロキシ（New Relic 公式 MCP）。アウトバウンドは API Key Credential Provider で認証
- ツールは自動検出・同期する（`listing_mode = DEFAULT` で control plane にキャッシュ）
- Runtime 側は `mcp-proxy-for-aws` の `aws_iam_streamablehttp_client` で接続

### ツールバックエンド

| ターゲット     | 種別              | 言語       | 主なツール                                             |
| -------------- | ----------------- | ---------- | ------------------------------------------------------ |
| `aws-mcp`      | MCP Server (公式) | —          | 任意の AWS API (CloudWatch 含む) を `call_aws` で実行  |
| `rollbar-mcp`  | Lambda            | TypeScript | エラーアイテム一覧、詳細、デプロイ履歴、ステータス更新 |
| `newrelic-mcp` | MCP Server (公式) | —          | NRQL クエリ実行、エンティティ検索、アラート取得        |
| K8s ツール     | Runtime 組み込み  | Python     | Pod/Deployment/Service 一覧、ログ取得、イベント確認    |

## データフロー（インシデント調査の例）

```
1. ユーザー → "過去1時間の 5xx エラーを分析して"

2. Runtime: Memory を検索（関連する過去会話があれば context に追加）

3. Strands Agent → Bedrock モデル呼び出し
   モデルが get_active_alarms / analyze_log_group 等を選択

4. Runtime → Gateway (InvokeGateway, SigV4)
   Gateway → aws-mcp → CloudWatch API

5. Runtime → EKS API (VPC Peering 経由)
   K8s ツールで関連 Pod のステータス・ログを取得

6. 結果を受け取り、モデルが自然言語で分析結果を生成

7. Runtime → ユーザーへ SSE レスポンス

8. Runtime: 会話ターンを Memory に保存（CreateEvent）
```
