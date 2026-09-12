# Runtime Long-Running パターン

AgentCore Runtime のセッションライフサイクルと、長時間実行時の HealthyBusy 制御についてまとめる。

## プラットフォームのタイムアウト体系

| タイムアウト              | デフォルト | 変更可否                      | 備考                            |
| ------------------------- | ---------- | ----------------------------- | ------------------------------- |
| Request timeout           | 15 分      | 不可                          | 同期リクエストの上限            |
| Streaming max duration    | 60 分      | 不可                          | SSE/WebSocket の上限            |
| Async job max duration    | 8 時間     | 不可                          | 非同期ジョブの上限              |
| idleRuntimeSessionTimeout | 15 分      | 可 (`LifecycleConfiguration`) | idle 判定でセッション terminate |
| maxLifetime               | 8 時間     | 可 (`LifecycleConfiguration`) | セッションの絶対寿命            |

ref: https://docs.aws.amazon.com/bedrock-agentcore/latest/devguide/bedrock-agentcore-limits.html#runtime-service-limits

## /ping と HealthyBusy

プラットフォームは約 2 秒間隔で `/ping` を呼び出し、セッションの状態を判定する。

| `/ping` レスポンス | プラットフォームの解釈 | idleRuntimeSessionTimeout |
| ------------------ | ---------------------- | ------------------------- |
| `Healthy`          | セッションは idle      | カウントダウン進行        |
| `HealthyBusy`      | セッションは処理中     | カウントダウン停止        |

**重要**: HTTP リクエストが進行中でも、`/ping` が `Healthy` を返す限り idle 扱いになる。

## SDK の自動判定ロジック

`BedrockAgentCoreApp.get_current_ping_status()` の優先順位:

1. `force_ping_status()` で強制されたステータス
2. `@app.ping` カスタムハンドラの戻り値
3. 自動判定: `_active_tasks` が空でなければ `HealthyBusy`、空なら `Healthy`

`add_async_task()` でタスクを登録すれば、カスタム `@app.ping` ハンドラなしで自動的に `HealthyBusy` が返る。

## 採用パターン: add_async_task (health tracking)

```python
task_id = app.add_async_task("agent_invoke", {"session_id": session_id})
try:
    result = await asyncio.to_thread(agent, context_prompt)
    yield {"text": str(result), "sessionId": session_id}
finally:
    app.complete_async_task(task_id)
```

- entrypoint 内で同期的に結果を返す（Slack bot が応答を待つため）
- `add_async_task` / `complete_async_task` で `/ping` が処理中に `HealthyBusy` を返す
- `complete_async_task` は `finally` で必ず呼ぶ（呼び忘れると `maxLifetime` まで課金が継続）

### 不採用: asyncio.create_task (fire-and-forget)

即座に `{"status": "started"}` を返してバックグラウンド処理するパターン。15 分超の処理に必要だが、呼び出し元（Slack bot）が結果を受け取る手段がなくなるため不採用。ポーリングまたはコールバック機構が必要になる。

### 不採用: @app.ping カスタムハンドラ

SDK の自動判定（`_active_tasks` ベース）で十分。カスタムハンドラが必要になるのは、タスク数以外の条件（メモリ使用量、外部依存の死活、graceful drain）で判定したい場合。

## 参考

- https://zenn.dev/aws_japan/articles/agentcore-async-long-running-patterns
- https://github.com/SeongHaedu/amazon-bedrock-agentcore-async-long-running-samples
