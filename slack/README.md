# Slack App セットアップ

Slack から Bedrock AgentCore のエージェントを呼び出すための設定。

## アーキテクチャ

```
Slack (@mention)
    │
    ▼
Lambda Function URL (HTTPS)  ← 1st invocation
    │  署名検証 → 即 200 OK → 自身を非同期 invoke
    ▼
Lambda (2nd invocation)
    │  InvokeAgentRuntime (AWS SDK)
    ▼
AgentCore Runtime
    │  Orchestrator → Investigation Agent → MCP Gateway
    ▼
Slack (chat.postMessage でスレッドに投稿)
```

## Slack App の作成

### 1. manifest から作成

1. https://api.slack.com/apps → **Create New App** → **From a manifest**
2. ワークスペースを選択
3. YAML タブで `slack-app-manifest.yaml` の内容を貼り付け
4. **Create**
5. **Install to Workspace** → 許可

### 2. トークンの取得

| 値                                | 場所                                | 用途                   |
| --------------------------------- | ----------------------------------- | ---------------------- |
| Bot User OAuth Token (`xoxb-...`) | OAuth & Permissions                 | `slack_bot_token`      |
| Signing Secret                    | Basic Information → App Credentials | `slack_signing_secret` |

`terraform/terraform.tfvars` に追加:

```hcl
slack_bot_token      = "xoxb-xxxxx"
slack_signing_secret = "xxxxx"
```

### 3. Lambda のデプロイ

```bash
# ビルド
cd app/lambda-slack-bot
npm install
npm run build

# Terraform apply（Lambda + Function URL 作成）
cd ../../terraform && terraform apply
```

### 4. Event Subscriptions の設定

1. Function URL を取得:

```bash
terraform output slack_bot_function_url
```

2. Slack App の設定画面:
   - **Event Subscriptions** → Enable Events → **ON**
   - Request URL に Function URL を貼り付け（Verified が出ればOK）
   - **Subscribe to bot events** → **Add Bot User Event** → `app_mention`
   - **Save Changes**

### 5. チャンネルへの招待

ボットを使いたいチャンネルに招待:

```
/invite @SRE Agent
```

## 使い方

チャンネルでボットをメンション:

```
@SRE Agent 過去1時間の CloudWatch アラームを一覧して
@SRE Agent Rollbar の最新エラーを見せて
@SRE Agent trocco の K8s Deployment のステータスを確認して
```

ボットはスレッドで「調査中です...」→ 結果を返す。

## Lambda の更新

```bash
cd app/lambda-slack-bot
npm run build
cd ../../terraform && terraform apply
```

Rollbar MCP と同じく `archive_file` で dist の変更を検知して自動アップロード。

## トラブルシューティング

### Request URL の Verified が出ない

- Lambda のログを確認:
  ```bash
  aws logs filter-log-events \
    --log-group-name "/aws/lambda/k-bedrock-agentcore-slack-bot" \
    --start-time $(($(date +%s) * 1000 - 600000)) \
    --profile pn-playground-admin \
    --region ap-northeast-1
  ```
- `SLACK_SIGNING_SECRET` が間違っている可能性

### メンションしても反応しない

- チャンネルにボットが招待されているか確認
- Event Subscriptions で `app_mention` が追加されているか確認
- Lambda のタイムアウト（デフォルト 120 秒）が短すぎないか確認

### タイムアウトする

AgentCore の応答が遅い場合、`terraform/variables.tf` の `slack_bot_lambda_timeout` を増やす（最大 900 秒）。
