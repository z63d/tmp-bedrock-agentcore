# Product Workload

AgentCore エージェントの接続先となる検証用 Product 環境。
VPC Peering で AgentCore VPC と接続し、エージェントが EKS / RDS に直接アクセスできるようにする。

## 構成

```
Product VPC (10.0.0.0/16)
├── public subnet  (10.0.0.0/24, 1a)    — NAT Gateway
├── EKS subnets    (10.0.10-11.0/24, 1a/1c)
├── RDS subnets    (10.0.20-21.0/24, 1a/1c)
│
├── EKS Cluster (product-workload)
│   └── Access Entries:
│       ├── Admin (SSO ロール) → AmazonEKSClusterAdminPolicy
│       └── AgentCore Runtime  → AmazonEKSViewPolicy
│
└── RDS MySQL (product-workload)
    └── agentcore-runtime ユーザー: Secrets Manager
```

## セットアップ

### 1. Terraform 変数の準備

`product-workload/terraform/terraform.tfvars` を作成:

```hcl
aws_profile              = "pn-playground-admin"
admin_role_arn           = "arn:aws:iam::<ACCOUNT_ID>:role/aws-reserved/sso.amazonaws.com/ap-northeast-1/AWSReservedSSO_AWSAdministratorAccess_<ID>"
agentcore_runtime_role_arn = "arn:aws:iam::<ACCOUNT_ID>:role/k-bedrock-agentcore-agentcore-runtime"
```

Admin ロール ARN の確認:

```bash
aws iam list-roles \
  --query "Roles[?contains(RoleName, 'AWSReservedSSO_AWSAdministratorAccess')].[Arn]" \
  --output text --profile pn-playground-admin
```

AgentCore Runtime ロール ARN の確認:

```bash
cd terraform && terraform output -raw agentcore_role_arn
```

### 2. Terraform apply

```bash
cd product-workload/terraform
terraform init
terraform apply
```

### 3. kubeconfig 設定

```bash
aws eks update-kubeconfig \
  --name product-workload \
  --profile pn-playground-admin \
  --region ap-northeast-1
```

### 4. サンプルアプリのデプロイ

```bash
kubectl apply -f product-workload/k8s/deployment.yaml
kubectl get pods
```

### 5. MySQL read-only ユーザーの作成

Terraform が `agentcore-runtime` ユーザーのパスワードを Secrets Manager に生成済み（ephemeral + write-only で state に残らない）。
MySQL にこのユーザーを作成する。

#### パスワードの取得

```bash
aws secretsmanager get-secret-value \
  --secret-id product-workload/rds-mysql-agentcore-runtime \
  --query 'SecretString' --output text \
  --profile pn-playground-admin --region ap-northeast-1 | jq -r .password
```

#### MySQL に接続

AWS コンソール → RDS → `product-workload` → **Actions** → **Connect with CloudShell** で接続。

#### ユーザー作成

```sql
-- read-only ユーザー作成
CREATE USER 'agentcore-runtime'@'%' IDENTIFIED BY '<上で取得したパスワード>';
GRANT SELECT ON app.* TO 'agentcore-runtime'@'%';
FLUSH PRIVILEGES;

-- 確認
SELECT user, host FROM mysql.user WHERE user = 'agentcore-runtime';
SHOW GRANTS FOR 'agentcore-runtime'@'%';
```

#### サンプルテーブルの作成

```sql
USE app;

CREATE TABLE users (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  email VARCHAR(255) NOT NULL UNIQUE,
  role ENUM('admin', 'member', 'viewer') NOT NULL DEFAULT 'member',
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- サンプルデータ
INSERT INTO users (name, email, role) VALUES
  ('test1', 'test1@example.com', 'admin'),
  ('test2', 'test2@example.com', 'member');
```

### 6. AgentCore 側の設定

`terraform/terraform.tfvars` に追加:

```hcl
eks_cluster_name = "product-workload"
mysql_secret_arn = "<rds_readonly_secret_arn の値>"
```

```bash
# 値の確認
cd product-workload/terraform
terraform output rds_readonly_secret_arn
```

VPC Peering を有効化して apply (product-workload を先に apply しておくこと):

```bash
cd terraform
terraform apply
```
