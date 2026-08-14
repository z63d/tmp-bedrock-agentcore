# ネットワーク・アーキテクチャの意思決定

AgentCore Runtime のネットワーク構成とセキュリティパターンの設計判断をまとめる。

## 採用パターン: Pattern 2 (VPC Connectivity via ENIs)

AWS が提示する [4 段階のネットワークパターン](https://aws.amazon.com/blogs/networking-and-content-delivery/network-connectivity-patterns-for-agents-deployed-on-amazon-bedrock-agentcore-runtime/) のうち、**Pattern 2** を採用した。

| Pattern | 概要 | 採否 |
|---|---|---|
| 1. Public Endpoint | デフォルト。全通信がインターネット経由 | 不採用 — Security Hub `BedrockAgentCore.1` 違反 |
| 2. VPC + ENI | private subnet に ENI 配置。private リソースに直接アクセス可 | **採用** |
| 3. VPC + PrivateLink | Pattern 2 + resource policy で public endpoint をブロック | 不採用 — 検証段階では過剰 |
| 4. Isolated VPC | インターネット完全遮断。全 AWS サービスを VPC Endpoint 経由 | 不採用 — 外部 MCP (New Relic) にアクセス不可 |

### 選定理由

- EKS / RDS など **private subnet のリソースに直接アクセス** する要件がある
- 外部 MCP サーバー (New Relic) へのアクセスが必要なため完全隔離 (Pattern 4) は不可
- 検証段階のため Pattern 3 (PrivateLink + resource policy) は YAGNI

## VPC 分離 + Peering

Runtime の ENI を Product VPC に直接置く案もあったが、**別 VPC + VPC Peering** を採用。

- **blast radius 分離**: AgentCore の SG / ルーティング変更が Product インフラに影響しない
- **Terraform state 分離**: `terraform/` と `product-workload/terraform/` で独立管理
- **ライフサイクルの違い**: AgentCore は高速にイテレーション、Product インフラは慎重に変更
- **Peering コスト**: 同一リージョン内は無料。データ転送 $0.01/GB は SRE エージェントの通信量では誤差

## ツールアクセスパターン

[AWS Security Blog](https://aws.amazon.com/blogs/security/secure-ai-agent-access-patterns-to-aws-resources-using-model-context-protocol/) の原則に基づく設計:

### 外部 API → Lambda MCP (Gateway 経由)

Rollbar / New Relic など外部 API は AgentCore Gateway 経由の MCP ツールとして実装。

- VPC アクセス不要
- Gateway の IAM 認証 (SigV4) で保護
- API Key は Credential Provider で管理（Lambda の環境変数に平文で置かない）

### Private インフラ → Runtime 直接アクセス

EKS / RDS など private リソースは Runtime コンテナから直接アクセス。

- Lambda MCP にしなかった理由:
  - ツール追加のたびに Lambda + IAM + Gateway Target が線形に増える
  - Lambda の 15 分タイムアウトがインシデント調査に不足
  - VPC に Runtime を置いた意味がなくなる
- 最小権限:
  - EKS: Access Entry で `AmazonEKSViewPolicy` (read-only)
  - RDS: read-only ユーザーで接続
  - Security Group で必要なポートのみ許可

### セキュリティ原則の適用

> "Any permission you grant to an agent can be exercised, regardless of your intended use case"

- Runtime の IAM ロールには必要最小限の権限のみ付与
- EKS は read-only (view) に制限 — kubectl exec / delete 等は不可
- RDS は read-only ユーザーで接続 — DROP / DELETE 等は不可
- SG の egress は全開放だが、EKS API (443) と RDS (3306) 以外は到達先がない

## VPC Endpoint の判断

Interface VPC Endpoint ($7.2/月/AZ) は `bedrock-runtime` のみ検討したが、現時点では全て NAT GW 経由とした。

- NAT GW がある時点でどれも必須ではない（コスト最適化の位置づけ）
- 検証段階で月 $36+ の endpoint 代は割高
- S3 Gateway Endpoint のみ採用（無料）
- 本番化時に `bedrock-runtime` / `ecr` / `logs` の追加を検討

## 参考

- [Network connectivity patterns for agents deployed on Amazon Bedrock AgentCore Runtime](https://aws.amazon.com/blogs/networking-and-content-delivery/network-connectivity-patterns-for-agents-deployed-on-amazon-bedrock-agentcore-runtime/)
- [Secure AI agent access patterns to AWS resources using Model Context Protocol](https://aws.amazon.com/blogs/security/secure-ai-agent-access-patterns-to-aws-resources-using-model-context-protocol/)
