# =============================================================================
# ec2.tf — EC2 Web Server in Public Subnet
#
# Step 2: Deploy EC2 instance in public subnet (web server)
#
# - Uses latest Amazon Linux 2023 AMI (free tier eligible)
# - Installs Nginx + PHP-FPM via user_data
# - SSH key pair generated locally by Terraform (TLS provider)
# - Placed in public subnet with auto-assigned public IP
# =============================================================================

# ── Latest Amazon Linux 2023 AMI ──────────────────────────────────────────────
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# ── TLS Private Key for SSH ────────────────────────────────────────────────────
resource "tls_private_key" "web_server" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# ── AWS Key Pair (upload public key) ──────────────────────────────────────────
resource "aws_key_pair" "web_server" {
  key_name   = "${var.project_name}-web-server-key"
  public_key = tls_private_key.web_server.public_key_openssh

  tags = {
    Name = "${var.project_name}-web-server-key"
  }
}

# ── Save Private Key Locally ───────────────────────────────────────────────────
resource "local_sensitive_file" "web_server_private_key" {
  content         = tls_private_key.web_server.private_key_pem
  filename        = "${path.module}/generated/${var.project_name}-web-server.pem"
  file_permission = "0600"
}

# ── EC2 Web Server Instance ────────────────────────────────────────────────────
resource "aws_instance" "web_server" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.web_server.key_name
  subnet_id                   = local.ec2_subnet_id
  vpc_security_group_ids      = [aws_security_group.ec2_web.id]
  associate_public_ip_address = true

  # Root EBS Volume — 20 GB gp3
  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true

    tags = {
      Name = "${var.project_name}-web-server-ebs"
    }
  }

  # ── Bootstrap script: Install Nginx + PHP + configure app ──────────────────
  user_data = base64encode(templatefile("${path.module}/templates/user_data.sh.tpl", {
    project_name  = var.project_name
    db_host       = aws_db_instance.mysql.address
    db_name       = var.db_name
    db_username   = var.db_username
    db_password   = var.db_password
    s3_bucket     = aws_s3_bucket.static_assets.id
    aws_region    = var.aws_region
  }))

  user_data_replace_on_change = true

  tags = {
    Name = "${var.project_name}-web-server"
    Role = "web-server"
  }

  depends_on = [
    aws_db_instance.mysql,
    aws_s3_bucket.static_assets
  ]
}
