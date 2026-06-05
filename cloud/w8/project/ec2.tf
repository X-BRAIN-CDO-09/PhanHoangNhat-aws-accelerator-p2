# =============================================================================
# ec2.tf — EC2 Instance running the kind Kubernetes cluster
#
# Uses Ubuntu 22.04 LTS (latest AMI via data source).
# The user_data script (templates/user_data.sh.tpl) is rendered with
# templatefile() and bootstraps Docker, kubectl, kind, and the K8s cluster.
# =============================================================================

# ── Latest Ubuntu 22.04 LTS AMI ───────────────────────────────────────────────
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
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

# ── Render user_data from template ────────────────────────────────────────────
locals {
  user_data_rendered = templatefile("${path.module}/templates/user_data.sh.tpl", {
    node_port    = var.node_port
    cluster_name = var.cluster_name
  })
}

# ── EC2 Instance ──────────────────────────────────────────────────────────────
resource "aws_instance" "k8s_host" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.ec2.key_name
  subnet_id                   = local.ec2_subnet_id
  vpc_security_group_ids      = [aws_security_group.ec2.id]
  associate_public_ip_address = true

  # Root EBS: 30 GB gp3 for Docker images + kind containers
  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
  }

  user_data                   = local.user_data_rendered
  user_data_replace_on_change = true

  tags = {
    Name = "${var.project_name}-k8s-host"
    Role = "kubernetes-host"
  }
}
