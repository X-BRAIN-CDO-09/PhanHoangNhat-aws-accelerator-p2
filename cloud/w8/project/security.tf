# =============================================================================
# security.tf — Security Groups for ALB and EC2
#
# Security rules:
#   ALB SG : Inbound  HTTP/80  from 0.0.0.0/0 (public internet)
#            Outbound ALL      to   0.0.0.0/0
#
#   EC2 SG : Inbound  SSH/22   from var.allowed_ssh_cidr (restricted)
#            Inbound  30080    ONLY from ALB Security Group (NOT public internet)
#            Outbound ALL      to   0.0.0.0/0
#
# KEY SECURITY DESIGN:
#   NodePort 30080 is NOT open to the public internet.
#   Only the ALB can reach the EC2 on port 30080, enforced via SG reference.
# =============================================================================

# ── ALB Security Group ────────────────────────────────────────────────────────
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Allow HTTP from internet to ALB"
  vpc_id      = local.vpc_id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-alb-sg"
  }
}

# ── EC2 Security Group ────────────────────────────────────────────────────────
resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-ec2-sg"
  description = "Allow SSH from restricted CIDR and NodePort only from ALB"
  vpc_id      = local.vpc_id

  # SSH — restricted to operator IP only (never 0.0.0.0/0)
  ingress {
    description = "SSH from allowed CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # NodePort — ONLY from ALB Security Group, NOT from the public internet
  ingress {
    description     = "NodePort from ALB only (not public)"
    from_port       = var.node_port
    to_port         = var.node_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ec2-sg"
  }
}
