# CloudWatch MCP Server 使い方ガイド

## 概要

CloudWatch MCP Serverは、自然言語でCloudWatchのメトリクス、アラーム、ログを照会・分析できる機能を提供します。

## クイックスタート

### 1. デプロイ

```bash
# Lambda Dockerイメージのビルド
cd lambda/cloudwatch-mcp
docker build -t cloudwatch-mcp-server .

# ECRにプッシュ
aws ecr get-login-password --region ap-northeast-1 | \
  docker login --username AWS --password-stdin $(terraform output -raw cloudwatch_mcp_ecr_repository_url)

docker tag cloudwatch-mcp-server:latest \
  $(terraform output -raw cloudwatch_mcp_ecr_repository_url):latest

docker push $(terraform output -raw cloudwatch_mcp_ecr_repository_url):latest

# Terraform適用
cd terraform
terraform apply
```

### 2. 環境変数の設定

AgentCore Runtimeに以下の環境変数を追加:

```bash
GATEWAY_ARN=arn:aws:bedrock-agentcore:ap-northeast-1:123456789012:gateway/xxxxx
```

### 3. アプリケーションの再デプロイ

```bash
cd app
npm install
npm run build
./scripts/deploy.sh
```

## 利用例

### メトリクス関連

**EC2のCPU使用率を確認**
```
「過去1時間のEC2インスタンスi-1234567890abcdef0のCPU使用率を教えて」
```

**Lambdaの実行時間を分析**
```
「my-functionというLambda関数の過去24時間のDurationを分析して」
```

**メトリクスのトレンドを確認**
```
「RDSデータベースmydbのConnectionsメトリクスにトレンドはある？」
```

### アラーム関連

**アクティブなアラームを確認**
```
「現在発報中のCloudWatchアラームを全て教えて」
```

**特定のアラームの履歴を確認**
```
「HighCPUAlarmというアラームの過去の状態変化を見せて」
```

**アラームの詳細を確認**
```
「prod-で始まるアラームの中でALARM状態のものはある？」
```

### ログ関連

**ロググループの一覧**
```
「/aws/lambda/で始まるロググループを一覧表示して」
```

**エラーログの分析**
```
「/aws/lambda/my-function のロググループを分析して、エラーパターンを見つけて」
```

**Logs Insightsクエリの実行**
```
「/aws/lambda/my-functionで過去1時間のエラーログを検索して、エラーメッセージごとの件数を教えて」
```

## 利用可能なツール詳細

### get_metric_data

CloudWatchからメトリクスの時系列データを取得します。

**パラメータ**:
| 名前 | 必須 | 説明 |
|------|------|------|
| namespace | ○ | AWS/EC2, AWS/Lambda, AWS/RDS など |
| metric_name | ○ | CPUUtilization, Duration, Invocations など |
| dimensions | - | [{Name: "InstanceId", Value: "i-xxx"}] 形式 |
| period | - | 秒単位（デフォルト: 300） |
| stat | - | Average, Sum, Maximum, Minimum |

### analyze_metric

メトリクスの統計分析とトレンド検出を行います。

**パラメータ**:
| 名前 | 必須 | 説明 |
|------|------|------|
| namespace | ○ | メトリクスの名前空間 |
| metric_name | ○ | メトリクス名 |
| dimensions | - | メトリクスの次元 |
| hours | - | 分析対象の時間（デフォルト: 24時間） |

**出力**:
- 平均、最小、最大、標準偏差
- トレンド（increasing/decreasing/stable）
- 最新値

### get_active_alarms

現在アクティブなアラームを取得します。

**パラメータ**:
| 名前 | 必須 | 説明 |
|------|------|------|
| state_value | - | ALARM, INSUFFICIENT_DATA, OK（デフォルト: ALARM） |
| alarm_name_prefix | - | アラーム名のプレフィックスでフィルタ |

### get_alarm_history

特定のアラームの状態変化履歴を取得します。

**パラメータ**:
| 名前 | 必須 | 説明 |
|------|------|------|
| alarm_name | ○ | アラーム名 |
| max_records | - | 最大レコード数（デフォルト: 50） |

### describe_log_groups

CloudWatch Logsのロググループ一覧を取得します。

**パラメータ**:
| 名前 | 必須 | 説明 |
|------|------|------|
| log_group_name_prefix | - | ロググループ名のプレフィックス |
| limit | - | 最大件数（デフォルト: 50） |

### analyze_log_group

ロググループ内のエラーパターンや異常を分析します。

**パラメータ**:
| 名前 | 必須 | 説明 |
|------|------|------|
| log_group_name | ○ | ロググループ名 |
| hours | - | 分析対象の時間（デフォルト: 1時間） |
| filter_pattern | - | カスタムフィルターパターン |

### execute_log_insights_query

Logs Insightsクエリを実行します。

**パラメータ**:
| 名前 | 必須 | 説明 |
|------|------|------|
| log_group_name | ○ | クエリ対象のロググループ |
| query_string | ○ | Logs Insightsクエリ文字列 |
| limit | - | 最大結果数（デフォルト: 100） |

**クエリ例**:
```
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 20
```

## トラブルシューティング

### CloudWatch関連のクエリが標準Agentに行ってしまう

`main.ts`の`isCloudWatchRelatedPrompt()`関数がクエリを正しく分類できていない可能性があります。キーワードを追加するか、明示的に「CloudWatchで」と言及してください。

### ツール実行エラー

1. **権限エラー**: Lambda関数のIAMロールにCloudWatch/Logs権限があるか確認
2. **タイムアウト**: 複雑なLogs Insightsクエリは30秒を超える場合があります
3. **リソースが見つからない**: ロググループ名やメトリクス名が正確か確認

### Gateway接続エラー

1. `GATEWAY_ARN`環境変数が正しく設定されているか確認
2. AgentCore RuntimeのIAMロールに`bedrock-agentcore:InvokeGateway`権限があるか確認
3. Gateway Targetが正しく同期されているか確認:
   ```bash
   aws bedrock-agentcore get-gateway-target \
     --gateway-identifier $GATEWAY_ID \
     --target-identifier cloudwatch_mcp_server
   ```

## 制限事項

- Lambda関数のタイムアウトは30秒
- Logs Insightsクエリの結果は最大100件（カスタマイズ可能）
- 複数リージョンのデータは取得不可（デプロイされたリージョンのみ）
- 一部のカスタムメトリクス名前空間はサポートされない場合があります
