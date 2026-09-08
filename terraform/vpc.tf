#------------------------------------------------------------------------------
# VPC
#------------------------------------------------------------------------------

locals {
  vpc_cidr = "10.1.0.0/16"
}

resource "aws_vpc" "main" {
  cidr_block           = local.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}"
  }
}

#------------------------------------------------------------------------------
# Subnets (single AZ: ap-northeast-1d)
#------------------------------------------------------------------------------

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(local.vpc_cidr, 8, 0)
  availability_zone = "ap-northeast-1d"

  tags = {
    Name = "${var.project_name}-public"
  }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(local.vpc_cidr, 8, 10)
  availability_zone = "ap-northeast-1d"

  tags = {
    Name = "${var.project_name}-private"
  }
}

#------------------------------------------------------------------------------
# Internet Gateway
#------------------------------------------------------------------------------

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}"
  }
}

#------------------------------------------------------------------------------
# NAT Gateway
#------------------------------------------------------------------------------

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  tags = {
    Name = "${var.project_name}"
  }

  depends_on = [aws_internet_gateway.main]
}

#------------------------------------------------------------------------------
# Route Tables
#------------------------------------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-public"
  }
}

resource "aws_route" "public_igw" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-private"
  }
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

#------------------------------------------------------------------------------
# Security Group — AgentCore Runtime
#------------------------------------------------------------------------------

resource "aws_security_group" "agentcore_runtime" {
  name                   = "${var.project_name}-agentcore-runtime"
  vpc_id                 = aws_vpc.main.id
  description            = "AgentCore Runtime"
  revoke_rules_on_delete = true

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-agentcore-runtime"
  }
}

#------------------------------------------------------------------------------
# Security Group — Slack Bot Lambda
#------------------------------------------------------------------------------

resource "aws_security_group" "slack_bot_lambda" {
  name                   = "${var.project_name}-slack-bot-lambda"
  vpc_id                 = aws_vpc.main.id
  description            = "Slack Bot Lambda"
  revoke_rules_on_delete = true

  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-slack-bot-lambda"
  }
}

#------------------------------------------------------------------------------
# VPC Endpoints
#------------------------------------------------------------------------------

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name = "${var.project_name}-s3"
  }
}

resource "aws_security_group" "vpce" {
  name                   = "${var.project_name}-vpce"
  vpc_id                 = aws_vpc.main.id
  description            = "VPC Endpoints"
  revoke_rules_on_delete = true

  ingress {
    from_port = 443
    to_port   = 443
    protocol  = "tcp"
    security_groups = [
      aws_security_group.agentcore_runtime.id,
      aws_security_group.slack_bot_lambda.id,
    ]
  }

  tags = {
    Name = "${var.project_name}-vpce"
  }
}

resource "aws_vpc_endpoint" "bedrock_agentcore" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.bedrock-agentcore"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-bedrock-agentcore"
  }
}

resource "aws_vpc_endpoint" "bedrock_agentcore_gateway" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.bedrock-agentcore.gateway"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.vpce.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-bedrock-agentcore-gateway"
  }
}
