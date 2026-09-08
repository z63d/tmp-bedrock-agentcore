---
name: newrelic
description: New Relic を使ったインフラ・アプリケーション監視の調査手順
---

# New Relic Tool Usage

## K8s リソースの検索

K8s Deployment/Pod などは `get_entity` では見つからない。必ず `execute_nrql_query` を使うこと:

- Deployments: `SELECT * FROM K8sDeploymentSample WHERE deploymentName LIKE '%dbt%' SINCE 1 hour ago LIMIT 10`
- Pods: `SELECT * FROM K8sPodSample WHERE podName LIKE '%dbt%' SINCE 1 hour ago LIMIT 10`
- クラスター指定: `WHERE clusterName = 'xxx'` を追加
- 環境指定: `WHERE clusterName LIKE '%production%'` などで絞り込む

## get_entity

APM/Browser など Entity として登録されているリソースに使う。Always specify `domains` and `types`:

- APM Applications: domains=['APM'], types=['APPLICATION']
- Hosts: domains=['INFRA'], types=['HOST']
- Browser apps: domains=['BROWSER'], types=['APPLICATION']
- Alerts/Issues: domains=['AIOPS'], types=['ISSUE']

Use `name_pattern` with wildcards: '%dbt%' (contains), 'prod%' (starts with), '%api' (ends with).

## Empty results vs errors

- If `get_entity` returns no entities, report "該当エンティティが見つかりませんでした" — do NOT call it an internal error.
- If a tool returns no data, try alternative approaches (different domains/types, NRQL query, broader name_pattern) before giving up.
- Only report an actual error when the tool explicitly returns an error message.
