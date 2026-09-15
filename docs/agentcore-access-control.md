# AgentCore アクセス制御: 3 層モデル

AgentCore Gateway を通過する MCP ツール呼び出しに対して、3 つのレイヤーでアクセス制御を適用できる。

## リクエスト処理フロー

```
JWT 検証 → REQUEST Interceptor → Cedar Policy 評価 → ツール呼び出し
                                                          ↓
caller ← RESPONSE Interceptor ← [suppressOutput Guardrails] ← 応答
```

各レイヤーは独立して有効化でき、組み合わせて多層防御を構成する。

## 1. AgentCore Policy (Cedar)

宣言的な認可ルールエンジン。全 tool call を `permit` / `forbid` で判定する。レイテンシ **<1ms**。

- [ドキュメント](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/policy.html)
- [Cedar を選んだ理由 (AWS Security Blog)](https://aws.amazon.com/blogs/security/why-policy-in-amazon-bedrock-agentcore-chose-cedar-for-securing-agentic-workflows/)

### Cedar で使える要素

| 要素      | 内容                                                                                            |
| --------- | ----------------------------------------------------------------------------------------------- |
| Principal | `AgentCore::OAuthUser`（JWT の sub）or `AgentCore::IamEntity`（IAM 認証時）                     |
| Action    | `AgentCore::Action::"<TargetName>___<method>"` — MCP ツール名がそのまま Action になる           |
| Resource  | `AgentCore::Gateway::"<gateway-arn>"`                                                           |
| Context   | `context.input.*`（ツール入力）、`context.output.*`（ツール出力）、`context.system.now`（時刻） |

Principal は `principal.hasTag()` / `principal.getTag()` で JWT claim（`cognito:groups` 等）を参照できる。

### ポリシー作成方法

- **Cedar 直書き**: MCP tool description から Cedar schema を自動生成。存在しないツールやパラメータの参照をコンパイル時に検出
- **自然言語**: LLM が Cedar を生成 → スキーマ検証 → automated reasoning（形式検証）で論理エラー検出 → 修正ループ

Automated reasoning は「常に deny になる無意味なポリシー」「矛盾する条件」「変更の影響範囲」を数学的に検証する。パターンマッチではなくシンボリック推論。

### 例: 特定ツールのパラメータ制限

```cedar
// 特定チャンネルのみ許可
forbid(
  principal,
  action == AgentCore::Action::"slack-mcp___conversations_history",
  resource
) unless {
  context.input.channel in ["C0123GENERAL", "C0456TEAM"]
};
```

### 例: ロールベースアクセス制御

```cedar
// policyholders グループにはクレーム情報の取得を禁止
forbid(
  principal is AgentCore::OAuthUser,
  action == AgentCore::Action::"lakehouse-mcp___get_claims_summary",
  resource
) when {
  principal.hasTag("cognito:groups") &&
  principal.getTag("cognito:groups") like "*policyholders*"
};
```

### 向いていること

- ロールベース / 属性ベースの決定論的判定
- パラメータの allowlist / denylist
- 時間帯制限（`context.system.now`）
- ユーザーグループ別の権限分離

### できないこと

- 外部 DB / API の参照（評価は純粋関数）
- トークン交換 / 認証ヘッダの構築
- レスポンスの変換・加工

## 2. Gateway Interceptors (Lambda)

Lambda で任意コードを実行するフック。REQUEST（ツール呼び出し前）と RESPONSE（応答後）の 2 種。Gateway あたり最大 REQUEST 1 + RESPONSE 1。

- [Interceptors ブログ](https://aws.amazon.com/blogs/machine-learning/apply-fine-grained-access-control-with-bedrock-agentcore-gateway-interceptors/)
- [カスタム認証の実装 (AWS Security Blog)](https://aws.amazon.com/blogs/security/implement-custom-authentication-for-tools-integration-using-request-lambda-interceptor-in-agentcore-gateway/)

### Policy との決定的な違い

Policy は「許可 / 拒否」しかできない。Interceptor は**データを変換・追加・除去**できる。

### REQUEST Interceptor

ツール呼び出し前に実行。`passRequestHeaders: true` で JWT 含むヘッダーを受け取れる。

- JWT の claim を読んで downstream の認証ヘッダに変換（act-on-behalf パターン）
- Secrets Manager から credential を取得してリクエストに注入
- DynamoDB からユーザーの属性情報を取得して context を enrich → 後続の Cedar Policy 評価で利用
- `transformedGatewayResponse` を返すとツール呼び出し自体をスキップ（short-circuit）

```python
def handler(event, context):
    headers = event['mcp']['gatewayRequest']['headers']
    jwt_claims = decode_jwt(headers['Authorization'])
    body = event['mcp']['gatewayRequest']['body']
    body['params']['arguments']['_user_groups'] = jwt_claims['cognito:groups']
    return {
        "interceptorOutputVersion": "1.0",
        "mcp": {"transformedGatewayRequest": {"body": body}}
    }
```

### RESPONSE Interceptor

ツール応答後、caller 返却前に実行。元の request と response 両方を受信。

- レスポンスから機密情報をマスク / 除去
- レスポンス形式の変換
- 監査ログの送信

ストリーミング時は JSON-RPC id を持つイベントごとに複数回 invocation される（progress 通知等はスルー）。

### パフォーマンス

- ウォーム時: 平均 **~4.5ms**
- コールドスタート時: 数百 ms 追加
- Lambda 同期呼び出しの 6MB ペイロード制限あり（`RESPONSE_BODY` を payload filter で除外して回避可能）

### 向いていること

- 動的データ参照（外部 DB / API）
- トークン交換 / 認証変換（act-on-behalf）
- `tools/list` レスポンスのフィルタリング（ユーザーに見せるツール自体を制御）
- レスポンスの加工・マスキング

### できないこと

- 宣言的ルール管理（Lambda コードに埋もれて監査しにくい）
- 形式検証（Cedar の automated reasoning に相当する仕組みがない）

## 3. Guardrails in Policy

Bedrock Guardrails の検出能力を Cedar ポリシー内で使う統合。ツールの入出力**内容**を AI で評価する。2026/06 GA。

- [GA アナウンス](https://aws.amazon.com/about-aws/whats-new/2026/06/amazon-bedrock-agentcore-policy-guardrails-generally-available/)

### 検出できるもの

| Safeguard              | 検出対象                                                 |
| ---------------------- | -------------------------------------------------------- |
| `PromptAttack`         | JAILBREAK, PROMPT_INJECTION, PROMPT_LEAKAGE              |
| `ContentFilter`        | VIOLENCE, HATE, SEXUAL, MISCONDUCT, INSULTS              |
| `SensitiveInformation` | SSN, クレカ番号, EMAIL, PHONE, AWS_ACCESS_KEY 等 20 種超 |

各 safeguard は confidence スコア（0, 0.2, 0.4, 0.6, 0.8, 1.0 の離散値）を返す。閾値と比較して判定。

### suppressOutput

Cedar 標準の `permit` / `forbid` に加えて、Guardrails 統合で `suppressOutput` effect が追加された。ツール呼び出し**完了後**に出力を評価し、違反時にレスポンスを抑制する。

```cedar
// 入力: prompt injection 検出 → リクエスト自体をブロック
forbid(principal, action, resource)
when guardrails {
  BedrockGuardrails::PromptAttack(["PROMPT_INJECTION"],
    [context.input.prompt])["PROMPT_INJECTION"]
    .confidenceScore.greaterThan(decimal("0.6"))
};

// 出力: SSN 検出 → レスポンスを抑制
suppressOutput(principal, action, resource)
when guardrails {
  BedrockGuardrails::SensitiveInformation(["US_SOCIAL_SECURITY_NUMBER"],
    [context.output.text])["US_SOCIAL_SECURITY_NUMBER"]
    .confidenceScore.greaterThan(decimal("0.5"))
};
```

### Standalone Bedrock Guardrails との違い

- **Standalone Guardrails**: モデルの推論 I/O（Converse API 等）に適用
- **AgentCore Policy 内の Guardrails**: Gateway レイヤーでツール呼び出しの I/O に適用。エージェントコードの**外側**で動くため、エージェントがバイパスできない

### 制限事項

- `suppressOutput` ポリシーを 1 つでも追加すると**ストリーミングが実質無効化**される（出力全体をバッファリングして評価するため）
- `when guardrails {…}` と通常の `when {…}` は同一ポリシー内で混在不可
- Gateway Execution Role に `bedrock:InvokeGuardrailChecks` 権限が必要
- Guardrails API 呼び出し分のレイテンシが追加される

### 向いていること

- Prompt injection / jailbreak 検出
- PII 漏洩防止（出力のコンテンツフィルタリング）
- 有害コンテンツのブロック

### できないこと

- 構造的なアクセス制御（誰が何にアクセスできるか → Policy を使う）
- レスポンスの変換・加工（ブロックするか通すかの二択 → Interceptor を使う）

## 使い分け

| 判断基準                | Policy (Cedar)           | Interceptor (Lambda)  | Guardrails            |
| ----------------------- | ------------------------ | --------------------- | --------------------- |
| パラメータの allowlist  | **最適**                 | できるが過剰          | 不向き                |
| ロール / 属性ベース ACL | **最適**                 | 不向き                | 不向き                |
| 動的データに基づく判定  | 不可                     | **最適**              | 不可                  |
| トークン交換 / 認証変換 | 不可                     | **最適**              | 不可                  |
| `tools/list` のフィルタ | 不可                     | **最適**              | 不可                  |
| Prompt injection 検出   | 不可                     | 実装可能だが非効率    | **最適**              |
| PII 漏洩防止（出力）    | 不可                     | 実装可能              | **最適**              |
| レスポンス構造変換      | 不可                     | **最適**              | 不可                  |
| レイテンシ              | <1ms                     | ~5ms + cold start     | Guardrails API 分追加 |
| 監査性                  | 高（宣言的、形式検証可） | 低（Lambda 内に埋没） | 中（Cedar 内に記述）  |

### 組み合わせパターン

**パターン A: 静的ルールのみ（最小構成）**

Cedar Policy だけで完結。パラメータの allowlist やロール制限など、判定に外部データが不要な場合。

**パターン B: 動的コンテキスト + 静的ルール**

REQUEST Interceptor でユーザー属性を enrich → Cedar Policy で判定。例: DynamoDB からユーザーの所属チームを取得し、Cedar でチーム別の権限を評価。

**パターン C: 多層防御（フル構成）**

REQUEST Interceptor（認証変換）→ Cedar Policy（アクセス制御）→ Guardrails（入力の prompt injection 検出 + 出力の PII 検出）→ RESPONSE Interceptor（監査ログ送信）。
