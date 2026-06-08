# =============================================================================
# security.tf — Security Groups
#
# Step 5: Configure security groups to allow only required traffic
#
# Traffic Matrix:
#   ┌───────────────┬────────────────────────────────────────────────────┐
#   │ Resource      │ Allowed Inbound                                     │
#   ├───────────────┼────────────────────────────────────────────────────┤
#   │ EC2 Web SG    │ SSH/22  ← var.allowed_ssh_cidr                     │
#   │               │ HTTP/80 ← 0.0.0.0/0 (public web traffic)           │
#   │               │ HTTPS/443 ← 0.0.0.0/0                              │
#   ├───────────────┼────────────────────────────────────────────────────┤
#   │ RDS SG        │ MySQL/3306 ← EC2 Security Group ONLY               │
#   └───────────────┴────────────────────────────────────────────────────┘
# =============================================================================

# ── EC2 Web Server Security Group ─────────────────────────────────────────────
resource "aws_security_group" "ec2_web" {
  name        = "${var.project_name}-ec2-web-sg"
  description = "Security group for EC2 web server in public subnet"
  vpc_id      = local.vpc_id

  # --- Inbound Rules ---

  # SSH — restricted to operator IP (never open to 0.0.0.0/0 in production)
  ingress {
    description = "SSH from allowed CIDR only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # HTTP — public web traffic
  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS — public web traffic
  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # --- Outbound Rules ---
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ec2-web-sg"
  }
}

# ── RDS MySQL Security Group ───────────────────────────────────────────────────
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Security group for RDS MySQL in private subnet only EC2 web server access"
  vpc_id      = local.vpc_id

  # --- Inbound Rules ---

  # MySQL/Aurora — ONLY from EC2 web server security group (not public internet)
  ingress {
    description     = "MySQL from EC2 web server only"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_web.id]
  }

  # --- Outbound Rules ---
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}
