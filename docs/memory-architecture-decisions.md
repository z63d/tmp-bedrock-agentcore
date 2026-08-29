# メモリアーキテクチャの意思決定

AgentCore Memory の統合パターンと、セッション管理方式の設計判断をまとめる。

## 背景

Bedrock AgentCore Memory は 2 層構造を持つ:

| 層                          | 説明                                                                     | スコープ       |
| --------------------------- | ------------------------------------------------------------------------ | -------------- |
| **Short-Term Memory (STM)** | Events（生の会話履歴）。session_id 単位で管理                            | セッション内   |
| **Long-Term Memory (LTM)**  | Memory Records（会話から非同期抽出されたファクト）。namespace 単位で管理 | セッション横断 |

Strands SDK は AgentCore Memory との統合パターンを 5 つ提供している:

| #   | パターン                      | 特徴                                                           |
| --- | ----------------------------- | -------------------------------------------------------------- |
| 1   | AgentCoreMemorySessionManager | Agent の session_manager に渡して自動管理。推奨スタート地点    |
| 2   | CompactingSessionManager      | 上記の拡張。長い会話を自動要約・圧縮                           |
| 3   | Hooks API                     | HookProvider でライフサイクルイベントにフックしてカスタム制御  |
| 4   | AgentCoreMemorySaver          | LangGraph 用チェックポインター                                 |
| 5   | Direct MemoryClient           | boto3 / MemoryClient で直接 API 呼び出し。フレームワーク非依存 |

## 採用パターン: Pattern 5 (Direct MemoryClient)

**AgentCoreMemorySessionManager（Pattern 1）を不採用とし、Direct MemoryClient（Pattern 5）を採用した。**

### AgentCoreMemorySessionManager の制約

#### 1. session_id の動的変更が構造的に不可能

`AgentCoreMemoryConfig` は初期化時に `session_id` を固定する。公式ドキュメントでも「1 セッションにつき 1 つの Agent のみサポート」と明記されている。

このSREエージェントは Slack スレッドごとに異なる `session_id` を使う。SessionManager を使う場合、リクエストごとに Agent を再生成する必要がある。

```python
# SessionManager パターン: session_id が Agent に固定される
agent = Agent(session_manager=AgentCoreMemorySessionManager(
    agentcore_memory_config=AgentCoreMemoryConfig(session_id=session_id, ...),
))

# Direct MemoryClient パターン: Agent はステートレス、メモリ操作は外部
stm = await memory_client.get_conversation_history(session_id)  # STM: セッション履歴
ltm = await memory_client.search_memories(prompt)               # LTM: セマンティック検索
agent = create_orchestrator()                                    # リクエストごとに新規生成
result = agent(context_prompt)                                   # メモリコンテキスト付きプロンプト
await memory_client.store_conversation(session_id, prompt, str(result))
```

#### 2. toolUse/toolResult 分離バグ (strands-agents/sdk-python#1272)

`toolUse` と `toolResult` が別イベントとして保存される。`list_events` API はデフォルト最新 100 件しか返さないため、ツール多用時に `toolUse` が切り落とされて `toolResult` だけ残り、Bedrock がバリデーションエラーを投げる。

SRE エージェントは MCP Gateway（New Relic / CloudWatch / Rollbar）、Kubernetes ツール、MySQL ツールを頻繁に呼ぶため、100 イベント超えは日常的に発生しうる。

#### 3. LTM 検索タイミングの制御不可

SessionManager は `create_session()` 時（Agent 初期化時）に 1 回だけ LTM 検索を実行する。リクエストごとにユーザーのプロンプトを検索クエリとして使いたい場合、この自動検索では不十分。

Direct MemoryClient なら `invoke()` 内で毎回 `retrieve_memory_records(searchQuery=prompt)` を呼べる。

#### 4. 検索結果のプロンプト注入位置

SessionManager は検索結果を `<user_context>` XML タグで system_prompt 先頭に自動注入する。注入位置やフォーマットのカスタマイズはできない。

### 選定理由

| 観点                 | AgentCoreMemorySessionManager | Direct MemoryClient                  |
| -------------------- | ----------------------------- | ------------------------------------ |
| Agent ライフサイクル | session_id ごとに再生成必要   | **リクエストごとに生成（軽量）**     |
| ツール多用時の安定性 | Issue #1272 リスク            | **保存内容を制御可能**               |
| LTM 検索タイミング   | 初期化時 1 回                 | **リクエストごとに実行**             |
| 検索クエリ           | initialization_query or 自動  | **ユーザープロンプトをそのまま使用** |
| プロンプト注入       | XML タグで先頭固定            | **任意の位置・フォーマット**         |
| 実装コスト           | 低い                          | 中程度                               |
| 公式サポート         | 推奨スタート地点              | **公式パターンの一つ**               |

Direct MemoryClient は公式に認められた 5 つのパターンのうちの一つであり、非標準なワークアラウンドではない。

## 設計方針

### Agent の初期化戦略

Strands Agent は `self.messages` に会話履歴をインメモリで蓄積する。シングルトン Agent を複数セッション（Slack スレッド）で共有すると、スレッド間で会話が混入する。`agent.messages = []` による手動リセットも不完全（`event_loop_metrics`, `conversation_manager` 状態など他の内部状態が残る。`reset()` メソッドは未実装: strands-agents/sdk-python#329）。

Strands SDK の A2A サーバーでも、シングルトン Agent（`agent` パラメータ）は非推奨で、コンテキストごとに Agent を新規生成する `agentFactory` パターンが推奨されている。

これに従い、Agent のライフサイクルを以下のように分離する:

- **investigation_agent**: シングルトン（`_get_investigation_agent()`）。`as_tool(preserve_context=False)` 経由で呼ばれるため、毎回コンストラクション時の状態に自動リセットされる。session_manager 不要
- **orchestrator**: リクエストごとに新規生成（`create_orchestrator()`）。直接 `agent(prompt)` で呼ばれるため自動リセットが効かない。session_manager 不要（メモリ操作は Agent 外部で行う）
- ツール群（K8s / MySQL / MCP）は関数定義のみで、実際の外部接続はツール呼び出し時に遅延実行される。Agent 生成コストは軽い

### メモリ操作フロー

```
リクエスト受信 (session_id, prompt)
    │
    ├─ STM 復元: list_events(session_id)
    │   → 同一スレッドの過去の会話をプロンプトに注入
    │
    ├─ LTM 検索: retrieve_memory_records(searchQuery=prompt)
    │   → 他スレッドのファクトをプロンプトに注入
    │
    ├─ orchestrator 生成: create_orchestrator()
    │   → リクエストごとに新規 Agent（クリーンな self.messages）
    │
    ├─ Agent 呼び出し: orchestrator(context_prompt)
    │
    └─ 会話保存: create_event(session_id, user_message, assistant_message)
        → バックグラウンドで Memory Strategy が LTM を自動抽出
```

- Agent はステートレス。インメモリの会話履歴には依存しない
- STM（セッション履歴）は session_id 単位で AgentCore Memory に保存・復元される
- LTM（ファクト）は namespace 内で全セッション共有される
- スレッド A で話した内容がファクトとして抽出されれば、スレッド B の LTM 検索でヒットする
- LTM の抽出は非同期（10-30 秒遅延）のため、直前のターンの内容は STM からの復元に依存する

### 将来の移行パス

Issue #1272 の修正と session_id 動的変更のサポートが入れば、AgentCoreMemorySessionManager への移行を再検討する。Hooks API（Pattern 3）も中間的な選択肢として残す。
