# Google Workspace MCP Server 比較

SRE Agent から Google Drive/Docs を操作するための MCP Server 候補を比較する。

## 候補

|                  | taylorwilsdon/google_workspace_mcp                                                      | piotr-agier/google-drive-mcp           |
| ---------------- | --------------------------------------------------------------------------------------- | -------------------------------------- |
| 言語             | Python                                                                                  | TypeScript                             |
| バージョン       | 4.0.3                                                                                   | 2.9.0                                  |
| Stars            | 3,100+                                                                                  | 200+                                   |
| ライセンス       | MIT                                                                                     | MIT                                    |
| Google APIs      | Drive, Docs, Sheets, Slides, Calendar, Gmail, Forms, Tasks, Contacts, Chat, Apps Script | Drive, Docs, Sheets, Slides, Calendar  |
| ツール数         | 120+                                                                                    | 116                                    |
| HTTP Transport   | Streamable HTTP (`--transport streamable-http`)                                         | Streamable HTTP (`--transport http`)   |
| デフォルトポート | 8000 (`WORKSPACE_MCP_PORT`)                                                             | 3100 (`--port` / `MCP_HTTP_PORT`)      |
| バインドアドレス | 127.0.0.1                                                                               | 127.0.0.1 (`--host` / `MCP_HTTP_HOST`) |

## Service Account 認証の比較

ここが最大の差分。

### taylorwilsdon/google_workspace_mcp

- SA モードでは `USER_GOOGLE_EMAIL` が **必須**（未設定だと `sys.exit(1)`）
- SA は常に指定ユーザーを impersonate する前提 → **Domain-Wide Delegation (DWD) 必須**
- DWD なしの SA 単体運用（共有ドライブのみアクセス）は**不可**

```python
# main.py:810-815
if is_service_account_enabled():
    user_email = os.getenv("USER_GOOGLE_EMAIL")
    if not user_email:
        sys.exit(1)  # 無条件で終了
```

環境変数:

- `GOOGLE_SERVICE_ACCOUNT_KEY_FILE` — SA キーファイルパス
- `GOOGLE_SERVICE_ACCOUNT_KEY_JSON` — SA キー JSON (インライン)
- `USER_GOOGLE_EMAIL` — impersonate 先ユーザー（**必須**）
- `DWD_ALLOWED_DOMAINS` — impersonate 許可ドメイン（任意）

### piotr-agier/google-drive-mcp

- SA モードは `GOOGLE_APPLICATION_CREDENTIALS` だけで動く
- `GOOGLE_DRIVE_MCP_SUBJECT` は**任意** — 未設定なら SA 自身として動作
- DWD なしの SA 単体運用（共有ドライブのみアクセス）が**可能**

```typescript
// externalAuth.ts
const subject = process.env.GOOGLE_DRIVE_MCP_SUBJECT?.trim();
// subject がなければ impersonate なし → SA 自身の権限で動作
```

環境変数:

- `GOOGLE_APPLICATION_CREDENTIALS` — SA キー**ファイルパス**（JSON inline 不可）
- `GOOGLE_DRIVE_MCP_SUBJECT` — impersonate 先ユーザー（任意、DWD 時のみ）
- `GOOGLE_DRIVE_MCP_SCOPES` — スコープ制限（任意、例: `drive.file,documents`）

## Lambda デプロイ時の差異

|                     | taylorwilsdon                | piotr-agier                                                            |
| ------------------- | ---------------------------- | ---------------------------------------------------------------------- |
| ランタイム          | Python                       | Node.js                                                                |
| SA キー渡し方       | 環境変数 (JSON inline)       | **ファイルパス** → Lambda では `/tmp` に書き出すか、コンテナにバンドル |
| DWD なし SA         | 不可                         | 可                                                                     |
| JSON レスポンス強制 | `FASTMCP_JSON_RESPONSE=true` | 不明（MCP SDK 依存）                                                   |
| ホスト変更          | 不可（固定 `127.0.0.1`）     | `--host 0.0.0.0` / `MCP_HTTP_HOST`                                     |

## 結論

**DWD を使う場合**: どちらでも可。taylorwilsdon は Google Workspace 全域をカバーしておりツールが豊富。

**DWD なしで SA 単体運用する場合**: piotr-agier 一択。共有ドライブに SA を追加してアクセスするパターンが使える。

SRE Agent のユースケース（共有ドライブにインシデントレポートを自動生成等）で DWD 設定が不要な場合は piotr-agier が適している。
