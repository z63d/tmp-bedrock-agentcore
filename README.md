# bedrock-agentcore

Amazon Bedrock AgentCore 上で動く SRE / インシデント調査エージェントの検証用リポジトリ。

Strands Agents SDK で実装したエージェントをコンテナとして AgentCore Runtime にデプロイし、
AgentCore Memory（会話履歴のセマンティック検索）と AgentCore Gateway 経由の MCP ツール
（CloudWatch / Rollbar は自前 Lambda、New Relic は公式 MCP サーバー）を組み合わせて、ログ・メトリクス・エラーを横断的に調査する。

## ディレクトリ構成

| ディレクトリ             | 内容                                                            |
| ------------------------ | --------------------------------------------------------------- |
| `app/bedrock-agentcore-sre/` | AgentCore Runtime アプリ（Python / Strands Agents）             |
| `app/lambda-rollbar-mcp/`   | Rollbar MCP サーバー（TypeScript, Lambda）                      |
| `app/lambda-slack-bot/`     | Slack Bot（TypeScript, Lambda）                                 |
| `cli/`                      | Runtime を呼び出す CLI ツール（TypeScript）                     |
| `terraform/`                | インフラ定義（ECR / IAM / Runtime / Memory / Gateway / Lambda / VPC） |
| `product-workload/`         | 検証用 Product 環境（EKS / RDS / VPC）                         |
| `scripts/`                  | ビルド & デプロイスクリプト                                     |
| `docs/`                     | 設計・デプロイ・API リファレンス                                |

## クイックスタート

```bash
# 1. Rollbar MCP Lambda をビルド
cd app/lambda-rollbar-mcp && npm install && npm run build

# 2. Terraform で AWS リソースを作成（Runtime 以外）
cd terraform && terraform init && terraform apply

# 3. エージェント本体のコンテナをビルド & ECR に push
./scripts/deploy.sh

# 4. Terraform 再 apply（Runtime を作成）
cd terraform && terraform apply

# 5. CLI で呼び出す
cd cli && npm install && cp .env.example .env
# .env に AGENT_RUNTIME_ARN を設定してから
npm run cli -- "過去1時間の CloudWatch アラームを一覧して"
```

詳細は [`docs/deployment-guide.md`](docs/deployment-guide.md) を参照。

## ドキュメント

- [`docs/architecture.md`](docs/architecture.md) — システム構成・データフロー・IAM 権限
- [`docs/deployment-guide.md`](docs/deployment-guide.md) — デプロイ手順・ローカル開発・トラブルシューティング
- [`docs/memory-api-reference.md`](docs/memory-api-reference.md) — AgentCore Memory API リファレンス
</content>
