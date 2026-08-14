#------------------------------------------------------------------------------
# DB Subnet Group
#------------------------------------------------------------------------------

resource "aws_db_subnet_group" "main" {
  name       = var.project_name
  subnet_ids = aws_subnet.rds[*].id
}

#------------------------------------------------------------------------------
# Security Group
#------------------------------------------------------------------------------

resource "aws_security_group" "rds" {
  name_prefix = "${var.project_name}-rds-"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr, var.agentcore_vpc_cidr]
  }

  lifecycle {
    create_before_destroy = true
  }
}

#------------------------------------------------------------------------------
# RDS MySQL (minimal: db.t4g.micro, single-AZ, 20GB)
#------------------------------------------------------------------------------

resource "aws_db_instance" "main" {
  identifier     = var.project_name
  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t4g.micro"

  allocated_storage = 20
  storage_type      = "gp3"

  db_name                     = "app"
  username                    = "admin"
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az            = false
  publicly_accessible = false
  skip_final_snapshot = true
}
