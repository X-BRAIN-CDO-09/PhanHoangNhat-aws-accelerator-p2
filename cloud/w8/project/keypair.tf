# =============================================================================
# keypair.tf — Tự động tạo SSH Key Pair bằng TLS provider
#
# Flow:
#   tls_private_key.ec2  →  aws_key_pair.ec2  →  aws_instance.k8s_host
#                        →  local_sensitive_file.private_key (lưu .pem local)
#
# NOTE: Private key được lưu vào generated/ec2-key.pem với permission 0400.
#       File này đã có trong .gitignore — KHÔNG commit lên git.
# =============================================================================

# ── Generate RSA 4096-bit private key ─────────────────────────────────────────
resource "tls_private_key" "ec2" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# ── Upload public key lên AWS ──────────────────────────────────────────────────
resource "aws_key_pair" "ec2" {
  key_name   = "${var.project_name}-keypair"
  public_key = tls_private_key.ec2.public_key_openssh

  tags = {
    Name = "${var.project_name}-keypair"
  }
}

# ── Lưu private key vào local file (generated/ec2-key.pem) ───────────────────
resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.ec2.private_key_pem
  filename        = "${path.module}/generated/ec2-key.pem"
  file_permission = "0400"
}
