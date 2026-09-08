# アーキテクチャ

## システム構成図

[`architecture-diagram.html`](./architecture-diagram.html) を参照。

## ネットワーク構成

[`network-architecture-decisions.md`](./network-architecture-decisions.md) を参照。

## コンポーネント

### AgentCore Runtime (`apps/bedrock-agentcore-sre/`)

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

Agent はステートレス（リクエストごとに新規生成）。会話の記憶は全て AgentCore Memory に外部化。

- **STM（短期記憶）**: `ListEvents` でセッション内の会話履歴を復元
- **LTM（長期記憶）**: `RetrieveMemoryRecords` でセッション横断のファクトをセマンティック検索
- **保存**: `CreateEvent` で会話ターンを保存。バックグラウンドで Memory Strategy が LTM を自動抽出

Memory Strategy は `SEMANTIC` タイプ。namespace は `/strategies/{memoryStrategyId}/`（actorId 分離なし、全セッションで共有）。

リクエスト処理フロー:

1. `ListEvents(session_id)` で同一スレッドの過去の会話を復元 → `[Conversation history]`
2. `RetrieveMemoryRecords(prompt)` で関連ファクトを検索 → `[Long-term memory]`
3. Orchestrator を新規生成し、コンテキスト付きプロンプトで実行
4. Agent 実行後、会話ターンを `CreateEvent` で保存

設計判断の詳細は [`memory-architecture-decisions.md`](./memory-architecture-decisions.md) を参照。

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
1. ユーザー → Slack Bot Lambda → AgentCore Runtime (VPC Endpoint 経由)

2. STM 復元: ListEvents(session_id) で同一スレッドの会話履歴を取得
   LTM 検索: RetrieveMemoryRecords(prompt) で関連ファクトを取得

3. Orchestrator を新規生成（ステートレス）
   Strands Agent → Bedrock モデル呼び出し
   モデルが get_active_alarms / analyze_log_group 等を選択

4. Runtime → Gateway (InvokeGateway, SigV4)
   Gateway → aws-mcp → CloudWatch API

5. Runtime → EKS API (VPC Peering 経由)
   K8s ツールで関連 Pod のステータス・ログを取得

6. 結果を受け取り、モデルが自然言語で分析結果を生成

7. Runtime → ユーザーへ SSE レスポンス

8. Runtime: 会話ターンを Memory に保存（CreateEvent）
   → バックグラウンドで SEMANTIC Strategy がファクトを自動抽出 → LTM に反映
```
