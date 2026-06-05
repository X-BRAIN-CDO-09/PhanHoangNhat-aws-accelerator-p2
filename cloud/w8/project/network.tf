# =============================================================================
# network.tf — VPC and Subnet configuration
#
# DESIGN DECISION: Create a dedicated VPC instead of relying on the Default VPC.
# This ensures the project works in any AWS account regardless of whether the
# default VPC exists, and follows infrastructure-as-code best practices.
#
# Architecture:
#   VPC (10.0.0.0/16)
#     ├─ Public Subnet A (10.0.1.0/24) — AZ a
#     ├─ Public Subnet B (10.0.2.0/24) — AZ b  ← ALB requires ≥2 AZs
#     ├─ Internet Gateway
#     └─ Public Route Table (0.0.0.0/0 → IGW)
#
# NOTE: For production, use private subnets + NAT Gateway for EC2 instances.
# =============================================================================

# ── VPC ───────────────────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
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

# ── Public Subnets (2 AZs required by ALB) ───────────────────────────────────
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-subnet-public-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-subnet-public-b"
  }
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

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# ── Convenience locals (replaces data.aws_vpc.default / data.aws_subnets.public) ──
locals {
  vpc_id     = aws_vpc.main.id
  subnet_ids = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  # EC2 is placed in subnet A (any public subnet works for a single-node cluster)
  ec2_subnet_id = aws_subnet.public_a.id
}
