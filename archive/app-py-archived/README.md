# Bedrock AgentCore Python Application

AWS Bedrock AgentCoreランタイムで動作するPythonエージェントアプリケーション。

## 技術スタック

- Python 3.12+
- strands-agents (Agent Framework)
- bedrock-agentcore (Runtime SDK)
- mcp + mcp-proxy-for-aws (MCP統合)
- Pydantic (型検証)
- structlog (ロギング)

## セットアップ

### 前提条件

- Python 3.12以上
- [uv](https://github.com/astral-sh/uv) (推奨) または pip
- AWS CLI設定済み
- Docker (コンテナビルド用)

### ローカル開発

```bash
# 依存関係インストール
cd app-py
uv pip install -e .

# 環境変数設定
cp .env.example .env
# .envを編集

# 起動
python -m bedrock_agentcore_app.main
```

### 環境変数

| 変数名 | 必須 | デフォルト | 説明 |
|--------|------|-----------|------|
| AWS_REGION | - | ap-northeast-1 | AWSリージョン |
| BEDROCK_MODEL_ID | - | amazon.nova-lite-v1:0 | 使用するBedrockモデル |
| MEMORY_ID | - | - | AgentCore Memory ID（設定時にメモリ機能有効化） |
| GATEWAY_ARN | - | - | AgentCore Gateway ARN（設定時にMCPツール有効化） |

## デプロイ

### Dockerビルド

```bash
cd app-py
docker build -t bedrock-agent .
```

### ECRへのプッシュ

```bash
# プロジェクトルートから
./scripts/deploy.sh
```

### Terraformデプロイ

```bash
cd terraform
terraform plan
terraform apply
```

## アーキテクチャ

```
src/bedrock_agentcore_app/
├── main.py              # エントリポイント (BedrockAgentCoreApp)
├── agent/
│   └── factory.py       # Agent作成 + calculatorツール
├── mcp/
│   └── gateway_client.py # Gateway MCPクライアント
├── memory/
│   └── client.py        # Memory APIクライアント
└── responses_api/
    ├── cloudwatch_client.py  # CloudWatchツール
    └── rollbar_client.py     # Rollbarツール
```

## 機能

- **Agent**: strands-agentsベースのLLMエージェント
- **Calculator Tool**: 四則演算ツール（add, subtract, multiply, divide）
- **MCP統合**: Gateway経由でCloudWatch/Rollbarツールを利用可能
- **Memory**: 会話履歴の保存とセマンティック検索
- **ストリーミング**: レスポンスのストリーミング出力

## テスト呼び出し

```bash
curl -X POST http://localhost:8080/invoke \
  -H "Content-Type: application/json" \
  -d '{"prompt": "1 + 2 を計算して", "sessionId": "test-1"}'
```
