# =============================================================================
# outputs.tf — Terraform Output Values
#
# These values are displayed after `terraform apply` and can be queried with
# `terraform output <name>`.
# =============================================================================

# ── VPC ───────────────────────────────────────────────────────────────────────
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.private[*].id
}

output "nat_gateway_ip" {
  description = "Public IP of the NAT Gateway (used by private subnet resources)"
  value       = aws_eip.nat.public_ip
}

# ── EC2 ───────────────────────────────────────────────────────────────────────
output "ec2_public_ip" {
  description = "Public IP address of the EC2 web server"
  value       = aws_instance.web_server.public_ip
}

output "ec2_public_dns" {
  description = "Public DNS hostname of the EC2 web server"
  value       = aws_instance.web_server.public_dns
}

output "ec2_instance_id" {
  description = "Instance ID of the EC2 web server"
  value       = aws_instance.web_server.id
}

output "web_url" {
  description = "URL to access the web application"
  value       = "http://${aws_instance.web_server.public_ip}"
}

output "ssh_command" {
  description = "SSH command to connect to the EC2 web server"
  value       = "ssh -i generated/${var.project_name}-web-server.pem ec2-user@${aws_instance.web_server.public_ip}"
}

output "private_key_path" {
  description = "Local path to the generated SSH private key"
  value       = local_sensitive_file.web_server_private_key.filename
}

# ── RDS ───────────────────────────────────────────────────────────────────────
output "rds_endpoint" {
  description = "Connection endpoint for the RDS MySQL instance (host:port)"
  value       = aws_db_instance.mysql.endpoint
}

output "rds_hostname" {
  description = "Hostname of the RDS MySQL instance"
  value       = aws_db_instance.mysql.address
}

output "rds_port" {
  description = "Port of the RDS MySQL instance"
  value       = aws_db_instance.mysql.port
}

output "rds_db_name" {
  description = "Name of the MySQL database"
  value       = aws_db_instance.mysql.db_name
}

output "rds_username" {
  description = "Master username for RDS MySQL"
  value       = aws_db_instance.mysql.username
  sensitive   = true
}

# ── S3 ────────────────────────────────────────────────────────────────────────
output "s3_bucket_name" {
  description = "Name of the S3 bucket for static assets"
  value       = aws_s3_bucket.static_assets.id
}

output "s3_bucket_arn" {
  description = "ARN of the S3 bucket for static assets"
  value       = aws_s3_bucket.static_assets.arn
}

output "s3_bucket_region" {
  description = "AWS region where the S3 bucket is located"
  value       = aws_s3_bucket.static_assets.region
}

# ── Summary ───────────────────────────────────────────────────────────────────
output "architecture_summary" {
  description = "Summary of the deployed architecture"
  value = <<-EOT
    ============================================================
     Web App on AWS — Deployment Summary
    ============================================================
     VPC ID         : ${aws_vpc.main.id}
     Public Subnets : ${join(", ", aws_subnet.public[*].id)}
     Private Subnets: ${join(", ", aws_subnet.private[*].id)}
    
     EC2 Web Server : http://${aws_instance.web_server.public_ip}
     SSH            : ssh -i generated/${var.project_name}-web-server.pem ec2-user@${aws_instance.web_server.public_ip}
    
     RDS MySQL      : ${aws_db_instance.mysql.endpoint}
     Database       : ${aws_db_instance.mysql.db_name}
    
     S3 Bucket      : ${aws_s3_bucket.static_assets.id}
    ============================================================
  EOT
}
