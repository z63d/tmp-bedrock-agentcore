# デプロイガイド

## 前提条件

```bash
python --version   # 3.13 以上（app-py ローカル実行用）
uv --version       # app-py の依存解決
node --version     # v24 以上（TS Lambda / CLI 用）
docker --version   # arm64 ビルド必須
aws --version      # AWS CLI v2
terraform --version  # ~1.14
```

AWS 認証:

```bash
aws sso login --profile pn-playground-admin
aws sts get-caller-identity --profile pn-playground-admin
```

---

## デプロイ手順

AgentCore Runtime の作成には ECR にイメージが存在している必要がある。
Rollbar MCP Lambda は ZIP デプロイのため Terraform が直接アップロードする。

### Step 1: Terraform 変数の準備

`terraform/terraform.tfvars` を作成（git 管理外）:

```hcl
aws_profile          = "pn-playground-admin"
rollbar_access_token = "xxxxx"
newrelic_api_key     = "NRAK-xxxxx"  # Gateway → New Relic 公式 MCP のアウトバウンド認証用
```

### Step 2: Rollbar MCP Lambda のビルド

Terraform apply 前に dist を生成しておく必要がある。

```bash
cd lambda/rollbar-mcp
npm install
npm run build
```

### Step 3: 初回 Terraform apply

```bash
cd terraform
terraform init
terraform apply
```

ECR にイメージが無いため Runtime 作成でエラーになるが想定通り。
ECR リポジトリ・IAM ロール・Memory・Gateway・Rollbar MCP Lambda は正常に作成される。

### Step 4: コンテナイメージのビルド & push

```bash
# エージェント本体
./scripts/deploy.sh
```

スクリプトは `terraform output` から ECR URL を取得し、arm64 でビルドして push する。

> スクリプト内の `AWS_PROFILE` は `pn-playground-admin` 固定。別プロファイルなら書き換える。

### Step 5: Terraform 再 apply

```bash
cd terraform
terraform apply
```

ECR イメージが揃って Runtime が作成される。

---

## イメージ更新

### エージェント本体 (app-py)

```bash
./scripts/deploy.sh
```

push 後、Runtime はイメージの変更を自動検知しないため `update-agent-runtime` が必要:

```bash
cd terraform
RUNTIME_ID=$(terraform output -raw agent_runtime_id)
ECR_REPO=$(terraform output -raw ecr_repository_url)
ROLE_ARN=$(terraform output -raw agentcore_role_arn)
GATEWAY_ID=$(terraform output -raw gateway_id)
MEMORY_ID=$(terraform output -raw memory_id)

aws bedrock-agentcore-control update-agent-runtime \
  --agent-runtime-id "$RUNTIME_ID" \
  --agent-runtime-artifact "{\"containerConfiguration\": {\"containerUri\": \"$ECR_REPO:latest\"}}" \
  --role-arn "$ROLE_ARN" \
  --network-configuration '{"networkMode": "PUBLIC"}' \
  --environment-variables "{\"AWS_REGION\": \"ap-northeast-1\", \"BEDROCK_MODEL_ID\": \"anthropic.claude-3-haiku-20240307-v1:0\", \"MEMORY_ID\": \"$MEMORY_ID\", \"GATEWAY_ID\": \"$GATEWAY_ID\"}" \
  --profile pn-playground-admin \
  --region ap-northeast-1

# READY になるまで待機
aws bedrock-agentcore-control get-agent-runtime \
  --agent-runtime-id "$RUNTIME_ID" \
  --profile pn-playground-admin \
  --region ap-northeast-1 \
  --query 'status'
```

### MCP サーバー（Lambda）

```bash
cd lambda/rollbar-mcp
npm run build
cd ../terraform
terraform apply
```

Terraform が ZIP を再生成して Lambda に自動アップロードする。`source_code_hash` で差分を検知するため、dist に変更があれば自動で反映される。

---

## CLI の使い方

```bash
cd cli
npm install
cp .env.example .env
```

`.env` に `AGENT_RUNTIME_ARN` を設定する:

```bash
# 値を取得して .env に追記
echo "AGENT_RUNTIME_ARN=$(cd ../terraform && terraform output -raw agent_runtime_arn)" >> .env
```

| 変数                | 必須 | 説明                      |
| ------------------- | ---- | ------------------------- |
| `AGENT_RUNTIME_ARN` | ○    | AgentCore Runtime の ARN  |
| `AWS_REGION`        |      | 既定 `ap-northeast-1`     |
| `AWS_PROFILE`       |      | 使用する AWS プロファイル |

```bash
# 単発クエリ
npm run cli -- "過去1時間の CloudWatch アラームを一覧して"

# インタラクティブ（REPL）モード
npm run cli
npm run cli -- -i

# セッションを引き継いで再開
npm run cli -- -s "cli-abc123-1234567890"
```

---

## 動作確認

### Runtime ステータス確認

```bash
cd terraform
RUNTIME_ID=$(terraform output -raw agent_runtime_id)

aws bedrock-agentcore-control get-agent-runtime \
  --agent-runtime-id "$RUNTIME_ID" \
  --profile pn-playground-admin \
  --region ap-northeast-1 \
  --query 'status'
```

`"READY"` になるまで待つ。

### エージェント呼び出し

```bash
cd terraform
RUNTIME_ARN=$(terraform output -raw agent_runtime_arn)
SESSION_ID="test-session-$(date +%s)-abcdefghijklmnop"
PAYLOAD=$(printf '{"prompt":"Hello", "sessionId":"%s"}' "$SESSION_ID" | base64)

aws bedrock-agentcore invoke-agent-runtime \
  --agent-runtime-arn "$RUNTIME_ARN" \
  --payload "$PAYLOAD" \
  --content-type "application/json" \
  --accept "text/event-stream" \
  --runtime-session-id "$SESSION_ID" \
  --profile pn-playground-admin \
  --region ap-northeast-1 \
  response.json && cat response.json
```

期待レスポンス（SSE 形式）:

```
event: message
data: {"text":"Hello! How can I assist you today?","sessionId":"test-session-..."}
```

### Memory 動作確認

同じ `SESSION_ID` で複数回送信し、前の会話を覚えているか確認する:

```bash
cd terraform
RUNTIME_ARN=$(terraform output -raw agent_runtime_arn)
SESSION_ID="memory-test-$(date +%s)-abcdefghijklmnop"

# 1回目: 名前を伝える
PAYLOAD=$(printf '{"prompt":"Hello, my name is Kaita.", "sessionId":"%s"}' "$SESSION_ID" | base64)
aws bedrock-agentcore invoke-agent-runtime \
  --agent-runtime-arn "$RUNTIME_ARN" \
  --payload "$PAYLOAD" \
  --content-type "application/json" \
  --accept "text/event-stream" \
  --runtime-session-id "$SESSION_ID" \
  --profile pn-playground-admin \
  --region ap-northeast-1 \
  response.json && cat response.json

# 2回目: 名前を聞く（記憶されていれば正しく答える）
PAYLOAD=$(printf '{"prompt":"What is my name?", "sessionId":"%s"}' "$SESSION_ID" | base64)
aws bedrock-agentcore invoke-agent-runtime \
  --agent-runtime-arn "$RUNTIME_ARN" \
  --payload "$PAYLOAD" \
  --content-type "application/json" \
  --accept "text/event-stream" \
  --runtime-session-id "$SESSION_ID" \
  --profile pn-playground-admin \
  --region ap-northeast-1 \
  response.json && cat response.json
```

---

## ローカル開発

```bash
cd app-py
uv pip install --system -e ".[dev]"

# AWS_REGION / BEDROCK_MODEL_ID 等を設定（.env でも可）
export AWS_REGION=ap-northeast-1
export AWS_PROFILE=pn-playground-admin

python -m bedrock_agentcore_app.main
```

別ターミナルから:

```bash
# ヘルスチェック
curl http://localhost:8080/ping

# 呼び出し（sessionId は 33 文字以上必要）
curl -X POST http://localhost:8080/invocations \
  -H 'Content-Type: application/json' \
  -H 'x-amzn-bedrock-agentcore-runtime-session-id: test-session-123456789012345678901234567890' \
  -d '{"prompt":"Hello"}'
```

Docker でコンテナとして動かす場合:

```bash
cd app-py
docker build -t bedrock-agent .

docker run --rm \
  -e AWS_REGION=ap-northeast-1 \
  -e BEDROCK_MODEL_ID=amazon.nova-lite-v1:0 \
  -v ~/.aws:/root/.aws:ro \
  -e AWS_PROFILE=pn-playground-admin \
  -p 8080:8080 \
  bedrock-agent
```

---

## トラブルシューティング

### `Received error (415) from runtime`

`--content-type "application/json"` が抜けている。AWS CLI のデフォルトは `application/octet-stream` で Runtime が受け付けない。

### `Received error (406) from runtime`

`--accept "text/event-stream"` が抜けている。エージェントがストリーミングレスポンスを返すため必須。

### `Received error (400) from runtime`

payload の base64 エンコードを確認する:

```bash
echo "$PAYLOAD" | base64 -d
```

zsh では `!` が特殊文字として `\!` にエスケープされる。`printf` を使うか `!` を含まない文字列にする。

### `Missing sessionId`

`--runtime-session-id` は 33 文字以上必要。
また AgentCore は sessionId ヘッダーをコンテナに転送しないため、**payload の body にも `sessionId` を含める**こと。

### `Could not load credentials from any providers`

IAM ロールに `bedrock:InvokeModel` 権限があるか、`AWS_REGION` 環境変数が設定されているか確認する。

### Runtime が起動しない (`RuntimeClientError`)

コンテナのログを確認する:

```bash
cd terraform
RUNTIME_ID=$(terraform output -raw agent_runtime_id)

aws logs filter-log-events \
  --log-group-name "/aws/bedrock-agentcore/runtimes/$RUNTIME_ID-DEFAULT" \
  --start-time $(($(date +%s) * 1000 - 3600000)) \
  --profile pn-playground-admin \
  --region ap-northeast-1
```

よくある原因:

- Docker イメージが arm64 でビルドされていない
- 環境変数が不足している
- IAM ロールの権限が足りない

### Terraform 初回実行時の Runtime エラー

ECR にイメージが存在しないため起こる想定通りのエラー。Step 3 でイメージを push してから再度 `terraform apply` する。
</content>
