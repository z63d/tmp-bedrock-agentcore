# AgentCore Memory API リファレンス

このドキュメントでは、AWS CLIを使用してAgentCore Memoryの内容を確認する方法を説明します。

## 前提条件

```bash
# Memory IDを取得
MEMORY_ID=$(cd terraform && terraform output -raw memory_id)

# プロファイルとリージョン
PROFILE="pn-playground-admin"
REGION="ap-northeast-1"
```

---

## Memory の構造

AgentCore Memoryは以下の階層構造を持ちます:

```
Memory
├── Sessions (セッション)
│   └── Events (イベント = 会話履歴)
└── Memory Records (長期記憶 = 抽出されたファクト)
```

| コンポーネント | 説明 | 保持期間 |
|--------------|------|---------|
| **Events** | 生の会話履歴（USER/ASSISTANT） | `event_expiry_duration`で設定 |
| **Memory Records** | 会話から抽出されたファクト | 永続 |

---

## 1. Memory Records（長期記憶）の確認

会話から自動抽出されたファクト（例: "ユーザーの名前はKaita"）を確認します。

### list-memory-records

namespace配下の全メモリレコードを一覧取得:

```bash
aws bedrock-agentcore list-memory-records \
  --memory-id "$MEMORY_ID" \
  --namespace "/" \
  --profile $PROFILE \
  --region $REGION
```

**レスポンス例:**

```json
{
    "memoryRecordSummaries": [
        {
            "memoryRecordId": "mem-407d526c-b44f-4546-8da2-5cbb7c5a8065",
            "content": {
                "text": "The user likes Japanese idols."
            },
            "memoryStrategyId": "semantic_memory-X9TzZNBlUc",
            "namespaces": [
                "/strategies/semantic_memory-X9TzZNBlUc/actors/user/"
            ],
            "createdAt": "2026-03-01T23:35:15.048000+09:00"
        },
        {
            "memoryRecordId": "mem-54dc11e2-b348-4f48-8024-dac87520b41a",
            "content": {
                "text": "The user's name is Kaita."
            },
            "memoryStrategyId": "semantic_memory-X9TzZNBlUc",
            "namespaces": [
                "/strategies/semantic_memory-X9TzZNBlUc/actors/user/"
            ],
            "createdAt": "2026-03-01T23:28:49.900000+09:00"
        }
    ]
}
```

### retrieve-memory-records

セマンティック検索でメモリを取得:

```bash
aws bedrock-agentcore retrieve-memory-records \
  --memory-id "$MEMORY_ID" \
  --namespace "/" \
  --search-criteria '{"searchQuery": "Kaita", "topK": 5}' \
  --profile $PROFILE \
  --region $REGION
```

**パラメータ:**

| パラメータ | 説明 |
|-----------|------|
| `searchQuery` | 検索クエリ（セマンティック検索） |
| `topK` | 返す結果の最大数 |
| `memoryStrategyId` | 特定のストラテジーでフィルタ |

---

## 2. Sessions（セッション）の確認

### list-sessions

アクターのセッション一覧を取得:

```bash
aws bedrock-agentcore list-sessions \
  --memory-id "$MEMORY_ID" \
  --actor-id "user" \
  --profile $PROFILE \
  --region $REGION
```

**レスポンス例:**

```json
{
    "sessionSummaries": [
        {
            "sessionId": "memory-test-1772375523-abcdefghijklmnop",
            "actorId": "user",
            "createdAt": "2026-03-01T23:35:15.177000+09:00"
        },
        {
            "sessionId": "test-1772375646-abcdefghijklmnopqrstuvwxyz",
            "actorId": "user",
            "createdAt": "2026-03-01T23:34:08.203000+09:00"
        }
    ]
}
```

---

## 3. Events（会話履歴）の確認

### list-events

特定セッションの会話履歴を取得:

```bash
SESSION_ID="memory-test-1772375523-abcdefghijklmnop"

aws bedrock-agentcore list-events \
  --memory-id "$MEMORY_ID" \
  --session-id "$SESSION_ID" \
  --actor-id "user" \
  --profile $PROFILE \
  --region $REGION
```

**レスポンス例:**

```json
{
    "events": [
        {
            "eventId": "0000001772375782346#c5e4dee5",
            "eventTimestamp": "2026-03-01T23:36:22.346000+09:00",
            "payload": [
                {
                    "conversational": {
                        "content": { "text": "あなたのおすすめは?" },
                        "role": "USER"
                    }
                },
                {
                    "conversational": {
                        "content": { "text": "Kaita, あなたのおすすめは難しいですが..." },
                        "role": "ASSISTANT"
                    }
                }
            ],
            "branch": { "name": "main" }
        }
    ]
}
```

---

## 4. よく使うコマンド集

### 全メモリレコードを確認

```bash
MEMORY_ID=$(cd terraform && terraform output -raw memory_id)

aws bedrock-agentcore list-memory-records \
  --memory-id "$MEMORY_ID" \
  --namespace "/" \
  --profile pn-playground-admin \
  --region ap-northeast-1
```

### 特定のキーワードで検索

```bash
aws bedrock-agentcore retrieve-memory-records \
  --memory-id "$MEMORY_ID" \
  --namespace "/" \
  --search-criteria '{"searchQuery": "name"}' \
  --profile pn-playground-admin \
  --region ap-northeast-1
```

### 最新セッションの会話を確認

```bash
# 1. セッション一覧を取得
aws bedrock-agentcore list-sessions \
  --memory-id "$MEMORY_ID" \
  --actor-id "user" \
  --profile pn-playground-admin \
  --region ap-northeast-1

# 2. セッションIDを指定してイベントを取得
aws bedrock-agentcore list-events \
  --memory-id "$MEMORY_ID" \
  --session-id "<session-id>" \
  --actor-id "user" \
  --profile pn-playground-admin \
  --region ap-northeast-1
```

### jqでテキストのみ抽出

```bash
# メモリレコードのテキストのみ
aws bedrock-agentcore list-memory-records \
  --memory-id "$MEMORY_ID" \
  --namespace "/" \
  --profile pn-playground-admin \
  --region ap-northeast-1 \
  | jq -r '.memoryRecordSummaries[].content.text'

# 出力例:
# The user likes Japanese idols.
# The user's name is Kaita.
```

---

## 5. Memory API 一覧

| API | 用途 | 必須パラメータ |
|-----|------|---------------|
| `list-memory-records` | メモリレコード一覧 | `memoryId`, `namespace` |
| `retrieve-memory-records` | セマンティック検索 | `memoryId`, `namespace`, `searchCriteria` |
| `list-sessions` | セッション一覧 | `memoryId`, `actorId` |
| `list-events` | イベント一覧 | `memoryId`, `sessionId`, `actorId` |
| `get-event` | 特定イベント取得 | `memoryId`, `sessionId`, `actorId`, `eventId` |

---

## 6. 注意事項

### Memory Records の生成タイミング

- Memory Recordsは**非同期で生成**されます
- 会話直後は反映されていない場合があります
- 数秒〜数十秒待ってから確認してください

### namespace の指定

- `/` はルートnamespace（全てのレコードを取得）
- Memory Strategyで設定した`namespaces`パターンに基づいて格納されます
- 例: `/strategies/{memoryStrategyId}/actors/{actorId}/`

### IAM権限

Memory APIを使用するには以下の権限が必要です:

```json
{
  "Action": [
    "bedrock-agentcore:ListMemoryRecords",
    "bedrock-agentcore:RetrieveMemoryRecords",
    "bedrock-agentcore:ListSessions",
    "bedrock-agentcore:ListEvents",
    "bedrock-agentcore:GetEvent"
  ],
  "Resource": "arn:aws:bedrock-agentcore:${region}:${account}:memory/*"
}
```
