# Amazon Bedrock AgentCore + Strands Agents SDK デプロイメントガイド

このドキュメントでは、TypeScriptで作成したStrands AgentをAmazon Bedrock AgentCore Runtimeにデプロイする手順を説明します。

## 目次

1. [概要](#概要)
2. [前提条件](#前提条件)
3. [プロジェクト構造](#プロジェクト構造)
4. [Phase 1: ローカル開発環境のセットアップ](#phase-1-ローカル開発環境のセットアップ)
5. [Phase 2: AgentCore Runtimeへのデプロイ](#phase-2-agentcore-runtimeへのデプロイ)
6. [Phase 3: Memory統合](#phase-3-memory統合)
7. [トラブルシューティング](#トラブルシューティング)
8. [参考リンク](#参考リンク)

---

## 概要

### Amazon Bedrock AgentCore とは

Amazon Bedrock AgentCoreは、AIエージェントを本番環境で安全かつスケーラブルに運用するための新しいプラットフォームです。従来のBedrock Agentsとは異なり、**自分でエージェントコードを書いてコンテナとしてデプロイ**します。

### 従来のBedrock Agents vs AgentCore

| 項目 | 従来のBedrock Agents | AgentCore |
|------|---------------------|-----------|
| SDK | `@aws-sdk/client-bedrock-agent-runtime` | `@aws-sdk/client-bedrock-agentcore` |
| Terraform | `aws_bedrockagent_agent` | `aws_bedrockagentcore_agent_runtime` |
| API | `InvokeAgent` | `InvokeAgentRuntime` |
| デプロイ | AWS管理 | **自分でコンテナをデプロイ** |
| 実行時間 | 短時間 | 最大8時間 |
| フレームワーク | なし | Strands, LangGraph, CrewAI等 |

### 技術スタック

- **言語**: TypeScript
- **Agent SDK**: `@strands-agents/sdk`
- **Runtime SDK**: `bedrock-agentcore`
- **コンテナ**: Docker (arm64)
- **インフラ**: Terraform
- **レジストリ**: Amazon ECR

---

## 前提条件

### 必要なツール

```bash
# Node.js 24以上
node --version  # v24.x.x

# Docker
docker --version

# AWS CLI v2
aws --version

# Terraform 1.14以上
terraform --version
```

### AWS認証情報

```bash
# AWS SSOでログイン
aws sso login --profile pn-playground-admin

# 認証情報の確認
aws sts get-caller-identity --profile pn-playground-admin
```

### 必要なAWS権限

- ECR: リポジトリ作成、イメージプッシュ
- IAM: ロール作成
- Bedrock AgentCore: Runtime作成、呼び出し
- Bedrock: モデル呼び出し
- CloudWatch Logs: ログ確認

---

## プロジェクト構造

```
bedrock-agentcore-ts/
├── app/
│   ├── src/
│   │   ├── agent/
│   │   │   └── index.ts          # Strands Agent定義
│   │   └── main.ts               # エントリーポイント
│   ├── dist/                     # ビルド成果物
│   ├── Dockerfile
│   ├── package.json
│   └── tsconfig.json
├── terraform/
│   ├── main.tf                   # ECR + IAM + AgentCore Runtime
│   ├── variables.tf
│   └── outputs.tf
└── docs/
    └── deployment-guide.md       # このドキュメント
```

---

## Phase 1: ローカル開発環境のセットアップ

### 1.1 依存関係のインストール

```bash
cd app
npm install
```

**package.json** の主要な依存関係:

```json
{
  "dependencies": {
    "@strands-agents/sdk": "^0.1.5",
    "bedrock-agentcore": "^0.2.0",
    "zod": "^4.0.0"
  }
}
```

### 1.2 Strands Agentの定義

**app/src/agent/index.ts**:

```typescript
import { Agent, BedrockModel, tool } from "@strands-agents/sdk";
import { z } from "zod";

// カスタムツール: 計算機
const calculatorSchema = z.object({
  operation: z
    .enum(["add", "subtract", "multiply", "divide"])
    .describe("The mathematical operation to perform"),
  a: z.number().describe("First number"),
  b: z.number().describe("Second number"),
});

const calculator = tool({
  name: "calculator",
  description: "Perform mathematical calculations",
  inputSchema: calculatorSchema,
  callback: (input) => {
    switch (input.operation) {
      case "add":
        return `Result: ${input.a} + ${input.b} = ${input.a + input.b}`;
      case "subtract":
        return `Result: ${input.a} - ${input.b} = ${input.a - input.b}`;
      case "multiply":
        return `Result: ${input.a} * ${input.b} = ${input.a * input.b}`;
      case "divide":
        return `Result: ${input.a} / ${input.b} = ${input.a / input.b}`;
    }
  },
});

// Agent作成
export const agent = new Agent({
  model: new BedrockModel({
    region: process.env.AWS_REGION ?? "ap-northeast-1",
    modelId:
      process.env.BEDROCK_MODEL_ID ?? "anthropic.claude-3-haiku-20240307-v1:0",
    maxTokens: 4096,
  }),
  tools: [calculator],
  systemPrompt:
    "You are a helpful assistant. When asked to perform calculations, use the calculator tool.",
});
```

### 1.3 BedrockAgentCoreAppの実装

**app/src/main.ts**:

```typescript
import {
  BedrockAgentCoreApp,
  type RequestContext,
} from "bedrock-agentcore/runtime";
import { agent } from "./agent/index.js";

const app = new BedrockAgentCoreApp({
  invocationHandler: {
    process: async (payload: unknown, context: RequestContext) => {
      const { prompt } = payload as { prompt: string };
      console.log(`Session ${context.sessionId} - Received prompt:`, prompt);

      // invoke を使用して非ストリーミングレスポンスを返す
      const result = await agent.invoke(prompt);
      return {
        response: result.toString(),
        sessionId: context.sessionId,
      };
    },
  },
});

console.log("Starting AgentCore Runtime server on port 8080...");
app.run();
```

**ポイント**:
- `BedrockAgentCoreApp`はFastifyベースのHTTPサーバー
- `/ping` (ヘルスチェック) と `/invocations` (エージェント呼び出し) エンドポイントを自動で提供
- `sessionId`は`x-amzn-bedrock-agentcore-runtime-session-id`ヘッダーから取得

### 1.4 ローカルでの動作確認

```bash
# ビルド
npm run build

# 開発サーバー起動 (ローカルテスト用)
npm run dev
```

別ターミナルで:

```bash
# ヘルスチェック
curl http://localhost:8080/ping

# エージェント呼び出し
curl -X POST http://localhost:8080/invocations \
  -H "Content-Type: application/json" \
  -H "x-amzn-bedrock-agentcore-runtime-session-id: test-session-123456789012345678901234567890" \
  -d '{"prompt":"What is 5 + 3?"}'
```

---

## Phase 2: AgentCore Runtimeへのデプロイ

### 2.1 デプロイの流れ

AgentCore Runtimeを作成するにはECRイメージが必要なため、以下の順序でデプロイします:

1. **Step 1**: Terraform apply（ECR + IAMのみ作成、AgentCore Runtimeはエラー）
2. **Step 2**: Dockerイメージをビルド＆ECRにプッシュ
3. **Step 3**: Terraform apply（AgentCore Runtimeを作成）

### 2.2 Step 1: Terraformの初回実行

```bash
cd terraform

# 初期化
terraform init

# 適用（AgentCore Runtimeはエラーになるが、ECRとIAMは作成される）
terraform apply
```

**注意**: 初回実行時は、ECRにイメージが存在しないためAgentCore Runtimeの作成でエラーが発生します。これは想定通りの動作です。ECRリポジトリとIAMロールは正常に作成されます。

### 2.3 Step 2: Dockerイメージのビルドとプッシュ

#### 2.3.1 Dockerfile

**app/Dockerfile**:

```dockerfile
FROM node:24-slim

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev

COPY dist/ ./dist/

ENV NODE_ENV=production

EXPOSE 8080

CMD ["node", "dist/main.js"]
```

**重要**:
- `dotenv`は本番環境では不要なため、`devDependencies`に入れるか、main.tsから`import "dotenv/config"`を削除
- AgentCore Runtimeは**arm64のみ**サポート

#### 2.3.2 ビルドとプッシュ

```bash
cd app

# TypeScriptビルド
npm run build

# Dockerイメージビルド (arm64)
docker build --platform linux/arm64 -t bedrock-agent:latest .

# ECRログイン
ECR_URL=$(cd ../terraform && terraform output -raw ecr_repository_url)
aws ecr get-login-password --region ap-northeast-1 --profile pn-playground-admin | \
  docker login --username AWS --password-stdin ${ECR_URL%/*}

# タグ付けとプッシュ
docker tag bedrock-agent:latest $ECR_URL:latest
docker push $ECR_URL:latest
```

### 2.4 Step 3: Terraformの再実行

ECRにイメージがプッシュされたので、再度Terraformを実行してAgentCore Runtimeを作成します:

```bash
cd terraform

# AgentCore Runtimeを作成
terraform apply
```

これで全てのリソースが正常に作成されます。

### 2.5 イメージ更新時の手順

コードを変更してイメージを更新した場合:

```bash
# 1. ビルド＆プッシュ
cd app
npm run build
docker build --platform linux/arm64 -t bedrock-agent:latest .
docker push $ECR_URL:latest

# 2. AgentCore Runtimeを更新（AWS CLIを使用）
aws bedrock-agentcore-control update-agent-runtime \
  --agent-runtime-id "<runtime-id>" \
  --agent-runtime-artifact '{"containerConfiguration": {"containerUri": "<ecr-url>:latest"}}' \
  --role-arn "<role-arn>" \
  --network-configuration '{"networkMode": "PUBLIC"}' \
  --environment-variables '{"AWS_REGION": "ap-northeast-1", "BEDROCK_MODEL_ID": "amazon.nova-lite-v1:0"}' \
  --profile pn-playground-admin \
  --region ap-northeast-1

# 3. ステータスがREADYになるまで待機
aws bedrock-agentcore-control get-agent-runtime \
  --agent-runtime-id "<runtime-id>" \
  --profile pn-playground-admin \
  --region ap-northeast-1 \
  --query 'status'
```

### 2.6 動作確認

#### 2.6.1 Runtimeステータスの確認

```bash
aws bedrock-agentcore-control get-agent-runtime \
  --agent-runtime-id "<runtime-id>" \
  --profile pn-playground-admin \
  --region ap-northeast-1 \
  --query 'status'
```

`READY`になるまで待機します。

#### 2.6.2 エージェントの呼び出し

**重要**:
- `--content-type "application/json"` は必須（デフォルトの`application/octet-stream`では415エラー）
- `--accept "text/event-stream"` は必須（ストリーミングレスポンスのため、ないと406エラー）
- `sessionId`はpayload bodyにも含める必要がある（ヘッダーはコンテナに転送されない）

```bash
RUNTIME_ARN=$(cd terraform && terraform output -raw agent_runtime_arn)
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
  response.json

cat response.json
```

**期待されるレスポンス** (SSE形式):

```
event: message
data: {"text":"Hello! How can I assist you today?","sessionId":"test-session-..."
}
```

#### 2.6.3 ツール使用のテスト

```bash
SESSION_ID="test-calc-$(date +%s)-abcdefghijklmnop"
PAYLOAD=$(printf '{"prompt":"What is 5 + 3? Use the calculator.", "sessionId":"%s"}' "$SESSION_ID" | base64)

aws bedrock-agentcore invoke-agent-runtime \
  --agent-runtime-arn "$RUNTIME_ARN" \
  --payload "$PAYLOAD" \
  --content-type "application/json" \
  --accept "text/event-stream" \
  --runtime-session-id "$SESSION_ID" \
  --profile pn-playground-admin \
  --region ap-northeast-1 \
  response.json

cat response.json
```

---

## Phase 3: Memory統合

AgentCore Memoryを使用して、エージェントに会話履歴を記憶させます。

### 3.1 Terraformリソースの追加

**terraform/main.tf**に以下を追加:

```hcl
#------------------------------------------------------------------------------
# AgentCore Memory
#------------------------------------------------------------------------------

resource "aws_bedrockagentcore_memory" "main" {
  name                  = replace(var.project_name, "-", "_")
  description           = "Memory for ${var.project_name} agent"
  event_expiry_duration = 30
}

resource "aws_bedrockagentcore_memory_strategy" "semantic" {
  name       = "semantic_memory"
  memory_id  = aws_bedrockagentcore_memory.main.id
  type       = "SEMANTIC"
  namespaces = ["/strategies/{memoryStrategyId}/actors/{actorId}/"]
}
```

IAMロールにMemory権限を追加:

```hcl
{
  Sid    = "AgentCoreMemory"
  Effect = "Allow"
  Action = [
    "bedrock-agentcore:CreateSession",
    "bedrock-agentcore:GetSession",
    "bedrock-agentcore:ListSessions",
    "bedrock-agentcore:DeleteSession",
    "bedrock-agentcore:CreateEvent",
    "bedrock-agentcore:ListEvents",
    "bedrock-agentcore:RetrieveMemoryRecords",
    "bedrock-agentcore:IngestMemoryRecords",
    "bedrock-agentcore:ListMemoryRecords"
  ]
  Resource = "arn:aws:bedrock-agentcore:${var.aws_region}:${local.account_id}:memory/*"
}
```

Runtime環境変数に`MEMORY_ID`を追加:

```hcl
environment_variables = {
  AWS_REGION       = var.aws_region
  BEDROCK_MODEL_ID = "amazon.nova-lite-v1:0"
  MEMORY_ID        = aws_bedrockagentcore_memory.main.id
}
```

### 3.2 Memory動作確認

同じセッションIDで複数回リクエストを送信し、会話が記憶されているか確認します。

```bash
RUNTIME_ARN=$(cd terraform && terraform output -raw agent_runtime_arn)
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
  response.json

cat response.json
# => "Hi Kaita! ..."

# 2回目: 同じセッションで名前を尋ねる
PAYLOAD=$(printf '{"prompt":"What is my name?", "sessionId":"%s"}' "$SESSION_ID" | base64)
aws bedrock-agentcore invoke-agent-runtime \
  --agent-runtime-arn "$RUNTIME_ARN" \
  --payload "$PAYLOAD" \
  --content-type "application/json" \
  --accept "text/event-stream" \
  --runtime-session-id "$SESSION_ID" \
  --profile pn-playground-admin \
  --region ap-northeast-1 \
  response.json

cat response.json
# => "Your name is Kaita." ← 前の会話を記憶している
```

**注意**: プロンプトに`!`を含めるとzshでエスケープされ400エラーになります。`!`を含まない文字列を使用してください。

---

## トラブルシューティング

### よくあるエラーと解決方法

#### 1. `RuntimeClientError: An error occurred when starting the runtime`

**原因**: コンテナの起動に失敗

**確認方法**:
```bash
aws logs describe-log-streams \
  --log-group-name "/aws/bedrock-agentcore/runtimes/<runtime-id>-DEFAULT" \
  --profile pn-playground-admin
```

**解決方法**:
- Dockerイメージがarm64でビルドされているか確認
- 環境変数が正しく設定されているか確認
- IAMロールに必要な権限があるか確認

#### 2. `Received error (415) from runtime`

**原因**: Content-Typeが`application/octet-stream`（デフォルト）になっている

**解決方法**:
- `--content-type "application/json"` を**必ず**指定する
- AWS CLIはデフォルトで`application/octet-stream`を使用するが、AgentCore Runtime環境ではカスタムContent-Typeパーサーが正しく機能しない
- `application/json`を明示的に指定することで回避可能

#### 3. `Received error (400) from runtime`

**原因**: リクエストボディが不正

**確認方法**:
- payloadのbase64エンコードが正しいか確認
- JSONにエスケープ文字（`\!`など）が含まれていないか確認

```bash
# payloadの確認
echo "$PAYLOAD" | base64 -d
```

**注意**: シェル（特にzsh）では`!`が特殊文字として扱われ、`\!`にエスケープされることがあります。

```bash
# 悪い例: zshでは"Hello!"が"Hello\!"になる
PAYLOAD=$(echo -n '{"prompt": "Hello!"}' | base64)
echo $PAYLOAD | base64 -d  # => {"prompt": "Hello\!"}  ← 400エラーの原因

# 良い例: printfを使用
PAYLOAD=$(printf '{"prompt": "Hello"}' | base64)

# 良い例: !を含まない文字列を使用
PAYLOAD=$(echo -n '{"prompt": "Hello, how are you?"}' | base64)
```

#### 4. `Missing sessionId`

**原因**: sessionIdがリクエストに含まれていない

**解決方法**:
- `--runtime-session-id` オプションを追加（33文字以上必要）
- **重要**: AgentCoreはsessionIdヘッダーをコンテナに転送しないため、**payloadのbodyにも`sessionId`を含める必要がある**

```bash
# 正しい例: bodyにsessionIdを含める
SESSION_ID="test-session-$(date +%s)-abcdefghijklmnop"
PAYLOAD=$(printf '{"prompt":"Hello", "sessionId":"%s"}' "$SESSION_ID" | base64)

aws bedrock-agentcore invoke-agent-runtime \
  --agent-runtime-arn "$RUNTIME_ARN" \
  --runtime-session-id "$SESSION_ID" \
  --content-type "application/json" \
  --accept "text/event-stream" \
  --payload "$PAYLOAD" \
  response.json
```

#### 5. `Received error (406) from runtime`

**原因**: `Accept`ヘッダーが設定されていない

**解決方法**:
- `--accept "text/event-stream"` を追加する
- エージェントがストリーミングレスポンス（`async function*`）を返す場合は必須

#### 6. `Could not load credentials from any providers`

**原因**: AWS認証情報が見つからない

**確認方法**:
- IAMロールに`bedrock:InvokeModel`権限があるか確認
- AgentCore Runtimeの環境変数に`AWS_REGION`が設定されているか確認

#### 6. Terraform初回実行時のAgentCore Runtimeエラー

**原因**: ECRにイメージが存在しない

**解決方法**:
- これは想定通りの動作です
- イメージをプッシュした後に`terraform apply`を再実行してください

### CloudWatch Logsの確認

```bash
# ログストリーム一覧
aws logs describe-log-streams \
  --log-group-name "/aws/bedrock-agentcore/runtimes/<runtime-id>-DEFAULT" \
  --order-by LastEventTime \
  --descending \
  --profile pn-playground-admin

# ログイベント取得
aws logs filter-log-events \
  --log-group-name "/aws/bedrock-agentcore/runtimes/<runtime-id>-DEFAULT" \
  --start-time $(($(date +%s) * 1000 - 3600000)) \
  --profile pn-playground-admin
```

**注意**: アプリケーションの`console.log`出力はCloudWatch Logsに表示されない場合があります。

AgentCoreのログには主にトレースログ（`response_payload`など）が記録されますが、コンテナ内の`console.log`は表示されないことがあります。これはAgentCoreのログ収集の仕様によるものです。

機能が動作しているかどうかは、実際のレスポンス内容で確認してください。

### ローカルでのデバッグ

```bash
# AWS認証情報をマウントしてコンテナを起動
docker run --rm \
  -e AWS_REGION=ap-northeast-1 \
  -e BEDROCK_MODEL_ID=amazon.nova-lite-v1:0 \
  -v ~/.aws:/root/.aws:ro \
  -e AWS_PROFILE=pn-playground-admin \
  -p 8080:8080 \
  bedrock-agent:latest

# 別ターミナルでテスト
curl -X POST 'http://localhost:8080/invocations' \
  -H 'Content-Type: application/json' \
  -H 'x-amzn-bedrock-agentcore-runtime-session-id: test-session-123456789012345678901234567890' \
  -d '{"prompt":"Hello"}'
```

---

## 参考リンク

- [Amazon Bedrock AgentCore Documentation](https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/what-is-bedrock-agentcore.html)
- [Strands Agents SDK - TypeScript](https://strandsagents.com/latest/documentation/docs/user-guide/deploy/deploy_to_bedrock_agentcore/typescript/)
- [bedrock-agentcore-sdk-typescript (GitHub)](https://github.com/aws/bedrock-agentcore-sdk-typescript)
- [Amazon Bedrock AgentCore Samples (GitHub)](https://github.com/awslabs/amazon-bedrock-agentcore-samples)

---

## 変更履歴

| 日付 | 変更内容 |
|------|----------|
| 2026-03-01 | 初版作成 |
