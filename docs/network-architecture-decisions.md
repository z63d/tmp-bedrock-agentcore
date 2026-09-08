# ネットワーク・アーキテクチャの意思決定

AgentCore Runtime のネットワーク構成とセキュリティパターンの設計判断をまとめる。

## 採用パターン: Pattern 3 (VPC + PrivateLink + Resource Policy)

AWS が提示する [4 段階のネットワークパターン](https://aws.amazon.com/blogs/networking-and-content-delivery/network-connectivity-patterns-for-agents-deployed-on-amazon-bedrock-agentcore-runtime/) のうち、**Pattern 3** を採用した。

| Pattern | 概要 | 採否 |
|---|---|---|
| 1. Public Endpoint | デフォルト。全通信がインターネット経由 | 不採用 — Security Hub `BedrockAgentCore.1` 違反 |
| 2. VPC + ENI | private subnet に ENI 配置。private リソースに直接アクセス可 | Pattern 3 の前提として採用 |
| 3. VPC + PrivateLink | Pattern 2 + resource policy で public endpoint をブロック | **採用** |
| 4. Isolated VPC | インターネット完全遮断。全 AWS サービスを VPC Endpoint 経由 | 不採用 — 外部 MCP (New Relic) にアクセス不可 |

### 選定理由

- EKS / RDS など **private subnet のリソースに直接アクセス** する要件がある（Pattern 2）
- 外部 MCP サーバー (New Relic) へのアクセスが必要なため完全隔離 (Pattern 4) は不可
- Resource policy (`aws:SourceVpc` Deny) で AgentCore Runtime をインターネットから完全に隔離（Pattern 3）
- Runtime の VPC 接続は [AWS セキュリティベストプラクティス](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-security-best-practices.html#security-bp-network) でも推奨（private リソースアクセス + PrivateLink + VPC Flow Logs 監査）

### Pattern 3 の実装

Pattern 2 の VPC 接続に加えて、以下を追加:

- **VPC Endpoint（2つ）**:
  - `com.amazonaws.{region}.bedrock-agentcore` — Runtime / Memory API（`private_dns_enabled = true`）
  - `com.amazonaws.{region}.bedrock-agentcore.gateway` — MCP Gateway（`private_dns_enabled = true`）
- **Resource policy**: Slack Bot Lambda の IAM Role のみ Allow + `aws:SourceVpc` 条件で VPC 外からの全アクセスを Deny
- **Slack Bot Lambda を VPC に配置**: private subnet に ENI を配置し、VPC Endpoint 経由で AgentCore を呼び出す。Slack API への通信は NAT GW 経由

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

## VPC Endpoint

Pattern 3 の実装に必要な VPC Endpoint に加え、S3 Gateway Endpoint を採用:

| VPC Endpoint | タイプ | 用途 | private_dns | コスト |
|---|---|---|---|---|
| `s3` | Gateway | ECR イメージ取得等 | — | 無料 |
| `bedrock-agentcore` | Interface | Runtime / Memory API | `true` | ~$7.2/月/AZ |
| `bedrock-agentcore.gateway` | Interface | MCP Gateway | `true` | ~$7.2/月/AZ |

- `bedrock-runtime` / `ecr` / `logs` 等は NAT GW 経由。本番化時にコスト最適化で追加を検討

## Gateway Fronting（不採用）

[AWS ベストプラクティス](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-security-best-practices.html)では、Runtime の前に Gateway を配置して Guardrails やリクエストインターセプターを適用するパターンを推奨している。現時点では不採用とした。

### 不採用の理由

- **Guardrails の必要性が低い**: SRE エージェントは社内利用（Slack 経由、許可チャンネル・ユーザー制限あり）。PII フィルタリングや有害コンテンツ検出の優先度が低い
- **HTTP Runtime に Guardrails を適用するには OpenAPI schema が必要**: 現在の Runtime は HTTP protocol で、Gateway の Policy Engine を使うには schema 定義が追加で必要
- **Interceptor が buffered mode のみ**: ストリーミングレスポンスに非対応。レスポンス時間に影響する
- **既存 MCP Gateway は流用不可**: `protocol_type = "MCP"` の Gateway には Runtime target を追加できない。`protocol_type` 未設定の新 Gateway が別途必要
- **変更範囲が大きい**: 新 Gateway + Target + Resource Policy 変更 + Slack Bot の呼び出し先変更 + IAM 変更 + VPC Endpoint 追加

### 現在のアクセス制御

Gateway fronting なしでも以下の多層防御で保護されている:

- Resource Policy: `aws:SourceVpc` 条件で VPC 外からの全アクセスを Deny
- Resource Policy: Slack Bot Lambda の IAM Role のみ Allow
- Slack 署名検証 + チャンネル・ユーザー制限（アプリ層）
- Runtime の IAM Role は最小権限（read-only ツールのみ）
 
### 再検討の条件

- 外部ユーザー（社外）にエージェントを公開する場合
- PII を含むデータソース（顧客 DB 等）にアクセスする場合
- プロンプトインジェクション対策が必要になった場合

## 参考

- [Network connectivity patterns for agents deployed on Amazon Bedrock AgentCore Runtime](https://aws.amazon.com/blogs/networking-and-content-delivery/network-connectivity-patterns-for-agents-deployed-on-amazon-bedrock-agentcore-runtime/)
- [Secure AI agent access patterns to AWS resources using Model Context Protocol](https://aws.amazon.com/blogs/security/secure-ai-agent-access-patterns-to-aws-resources-using-model-context-protocol/)
- [Secure multi-tenant AI agents with Amazon Bedrock AgentCore resource-based policies](https://aws.amazon.com/blogs/security/secure-multi-tenant-ai-agents-with-amazon-bedrock-agentcore-resource-based-policies/)
- [Secure ingress connectivity to Amazon Bedrock AgentCore Gateway using interface VPC endpoints](https://aws.amazon.com/blogs/machine-learning/secure-ingress-connectivity-to-amazon-bedrock-agentcore-gateway-using-interface-vpc-endpoints/)
- [AgentCore Runtime security best practices](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/runtime-security-best-practices.html)
- [AgentCore VPC interface endpoints](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/vpc-interface-endpoints.html)
