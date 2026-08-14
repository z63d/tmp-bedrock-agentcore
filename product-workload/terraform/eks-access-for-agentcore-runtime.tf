#------------------------------------------------------------------------------
# EKS Access — AgentCore Runtime
#------------------------------------------------------------------------------

resource "aws_eks_access_entry" "agentcore_runtime" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.agentcore_runtime_role_arn
}

resource "aws_eks_access_policy_association" "agentcore_runtime_view" {
  cluster_name  = aws_eks_cluster.main.name
  principal_arn = var.agentcore_runtime_role_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"

  access_scope {
    type = "cluster"
  }
}
