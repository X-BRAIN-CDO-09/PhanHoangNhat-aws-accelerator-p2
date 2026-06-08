# =============================================================================
# network.tf — VPC Module: Public & Private Subnets
#
# Architecture:
#   VPC (10.0.0.0/16)
#     ├─ Public Subnet A  (10.0.1.0/24)  — AZ[0] — EC2 Web Server
#     ├─ Public Subnet B  (10.0.2.0/24)  — AZ[1] — (spare / ALB)
#     ├─ Private Subnet A (10.0.11.0/24) — AZ[0] — RDS Primary
#     ├─ Private Subnet B (10.0.12.0/24) — AZ[1] — RDS Standby (Multi-AZ)
#     ├─ Internet Gateway  → attached to public route table
#     ├─ NAT Gateway       → attached to private route table (EC2 EIP)
#     ├─ Public Route Table  (0.0.0.0/0 → IGW)
#     └─ Private Route Table (0.0.0.0/0 → NAT)
#
# Step 1 of the lab.
# =============================================================================

# ── Available AZs ──────────────────────────────────────────────────────────────
data "aws_availability_zones" "available" {
  state = "available"
}

# ── VPC ───────────────────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# ── Internet Gateway ──────────────────────────────────────────────────────────
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# ── Public Subnets ────────────────────────────────────────────────────────────
resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-subnet-public-${count.index + 1}"
    Type = "public"
    AZ   = data.aws_availability_zones.available.names[count.index]
  }
}

# ── Private Subnets ───────────────────────────────────────────────────────────
resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-subnet-private-${count.index + 1}"
    Type = "private"
    AZ   = data.aws_availability_zones.available.names[count.index]
  }
}

# ── Elastic IP for NAT Gateway ─────────────────────────────────────────────────
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-nat-eip"
  }

  depends_on = [aws_internet_gateway.main]
}

# ── NAT Gateway (in first public subnet) ──────────────────────────────────────
# Allows resources in private subnets to reach the internet (e.g., RDS patch downloads)
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.project_name}-nat-gw"
  }

  depends_on = [aws_internet_gateway.main]
}

# ── Public Route Table ────────────────────────────────────────────────────────
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-rtb-public"
  }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ── Private Route Table ───────────────────────────────────────────────────────
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-rtb-private"
  }
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ── Locals — convenience references used across other files ───────────────────
locals {
  vpc_id             = aws_vpc.main.id
  public_subnet_ids  = aws_subnet.public[*].id
  private_subnet_ids = aws_subnet.private[*].id

  # EC2 goes in first public subnet
  ec2_subnet_id = aws_subnet.public[0].id

  # RDS DB Subnet Group uses all private subnets (Multi-AZ ready)
  rds_subnet_ids = aws_subnet.private[*].id
}
