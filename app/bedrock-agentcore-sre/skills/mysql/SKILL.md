---
name: mysql
description: RDS MySQL (app データベース) の調査手順とスキーマ情報
---

# MySQL 調査

## 接続先

- データベース: `app`

## スキーマ

### users テーブル

| カラム     | 型                              | 説明               |
| ---------- | ------------------------------- | ------------------ |
| id         | BIGINT (PK)                     |                    |
| name       | VARCHAR(100)                    |                    |
| email      | VARCHAR(255)                    | UNIQUE             |
| role       | ENUM('admin','member','viewer') | デフォルト: member |
| created_at | TIMESTAMP                       |                    |
| updated_at | TIMESTAMP                       |                    |

## ツール

- `mysql_show_tables` — テーブル一覧
- `mysql_describe_table` — カラム定義
- `mysql_execute_query` — SELECT / SHOW / DESCRIBE / EXPLAIN のみ実行可能

## Tips

- 大量データを返すクエリは `LIMIT` をつけること
