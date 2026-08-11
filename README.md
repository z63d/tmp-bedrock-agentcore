# bedrock-agentcore

Amazon Bedrock AgentCore 上で動く SRE / インシデント調査エージェントの検証用リポジトリ。

Strands Agents SDK で実装したエージェントをコンテナとして AgentCore Runtime にデプロイし、
AgentCore Memory（会話履歴のセマンティック検索）と AgentCore Gateway 経由の MCP ツール
（CloudWatch / Rollbar / New Relic）を組み合わせて、ログ・メトリクス・エラーを横断的に調査する。

## ディレクトリ構成

| ディレクトリ             | 内容                                                            |
| ------------------------ | --------------------------------------------------------------- |
| `app-py/`                | **現行**の AgentCore Runtime アプリ（Python / Strands Agents）  |
| `cli/`                   | Runtime を呼び出す CLI ツール（TypeScript）                     |
| `lambda/cloudwatch-mcp/` | CloudWatch MCP サーバー（Python, Lambda）                       |
| `lambda/rollbar-mcp/`    | Rollbar MCP サーバー（TypeScript, Lambda）                      |
| `lambda/newrelic-mcp/`   | New Relic MCP サーバー（TypeScript, Lambda）                    |
| `terraform/`             | インフラ定義（ECR / IAM / Runtime / Memory / Gateway / Lambda） |
| `scripts/`               | ビルド & デプロイスクリプト                                     |
| `docs/`                  | 設計・デプロイ・API リファレンス                                |

## クイックスタート

```bash
# 1. Terraform で AWS リソースを作成
cd terraform && terraform init && terraform apply

# 2. コンテナをビルド & ECR に push
./scripts/deploy.sh
./scripts/deploy-cloudwatch-mcp.sh  # 使うものだけ
./scripts/deploy-rollbar-mcp.sh
./scripts/deploy-newrelic-mcp.sh

# 3. Terraform 再 apply（Runtime を作成）
cd terraform && terraform apply

# 4. CLI で呼び出す
cd cli && npm install && cp .env.example .env
# .env に AGENT_RUNTIME_ARN を設定してから
npm run cli -- "過去1時間の CloudWatch アラームを一覧して"
```

詳細は [`docs/deployment-guide.md`](docs/deployment-guide.md) を参照。

## ドキュメント

- [`docs/architecture.md`](docs/architecture.md) — システム構成・データフロー・IAM 権限
- [`docs/deployment-guide.md`](docs/deployment-guide.md) — デプロイ手順・ローカル開発・トラブルシューティング
- [`docs/memory-api-reference.md`](docs/memory-api-reference.md) — AgentCore Memory API リファレンス
- [`docs/cloudwatch-mcp-usage.md`](docs/cloudwatch-mcp-usage.md) — CloudWatch MCP の使い方
</content>
