#------------------------------------------------------------------------------
# VPC Peering — AgentCore ↔ Product Workload
#------------------------------------------------------------------------------

data "aws_vpc" "product_workload" {
  count = var.enable_vpc_peering ? 1 : 0

  tags = {
    Name = "product-workload"
  }
}

data "aws_route_table" "product_workload_private" {
  count  = var.enable_vpc_peering ? 1 : 0
  vpc_id = data.aws_vpc.product_workload[0].id

  tags = {
    Name = "product-workload-private"
  }
}

resource "aws_vpc_peering_connection" "product_workload" {
  count       = var.enable_vpc_peering ? 1 : 0
  vpc_id      = aws_vpc.main.id
  peer_vpc_id = data.aws_vpc.product_workload[0].id
  auto_accept = true

  tags = {
    Name = "${var.project_name}-to-product-workload"
  }
}

# AgentCore → Product Workload
resource "aws_route" "product_workload" {
  count                     = var.enable_vpc_peering ? 1 : 0
  route_table_id            = aws_route_table.private.id
  destination_cidr_block    = data.aws_vpc.product_workload[0].cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.product_workload[0].id
}

# Product Workload → AgentCore
resource "aws_route" "product_to_agentcore" {
  count                     = var.enable_vpc_peering ? 1 : 0
  route_table_id            = data.aws_route_table.product_workload_private[0].id
  destination_cidr_block    = local.vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.product_workload[0].id
}
