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
│   ├── Node Group: t3.medium x1
│   └── Access Entries:
│       ├── Admin (SSO ロール) → AmazonEKSClusterAdminPolicy
│       └── AgentCore Runtime  → AmazonEKSViewPolicy (read-only)
│
└── RDS MySQL (product-workload)
    ├── db.t4g.micro, 20GB gp3
    ├── single-AZ
    └── パスワード: Secrets Manager 管理 (manage_master_user_password)
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

### 5. AgentCore 側の設定

`terraform/terraform.tfvars` に EKS クラスター名を追加:

```hcl
eks_cluster_name = "product-workload"
```

VPC Peering を有効化 (product-workload を先に apply しておくこと):

```bash
cd terraform
terraform apply
```
