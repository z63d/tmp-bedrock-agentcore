#------------------------------------------------------------------------------
# VPC Peering — AgentCore ↔ Product Workload
#------------------------------------------------------------------------------

data "aws_vpc" "product_workload" {
  tags = {
    Name = "product-workload"
  }
}

data "aws_route_table" "product_workload_private" {
  vpc_id = data.aws_vpc.product_workload.id

  tags = {
    Name = "product-workload-private"
  }
}

resource "aws_vpc_peering_connection" "product_workload" {
  vpc_id      = aws_vpc.main.id
  peer_vpc_id = data.aws_vpc.product_workload.id
  auto_accept = true

  tags = {
    Name = "${var.project_name}-to-product-workload"
  }
}

# AgentCore → Product Workload
resource "aws_route" "product_workload" {
  route_table_id            = aws_route_table.private.id
  destination_cidr_block    = data.aws_vpc.product_workload.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.product_workload.id
}

# Product Workload → AgentCore
resource "aws_route" "product_to_agentcore" {
  route_table_id            = data.aws_route_table.product_workload_private.id
  destination_cidr_block    = local.vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.product_workload.id
}
