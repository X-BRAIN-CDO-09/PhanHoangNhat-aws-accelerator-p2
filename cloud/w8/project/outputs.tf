# =============================================================================
# outputs.tf — Terraform outputs
# =============================================================================

output "alb_dns_name" {
  description = "ALB DNS name — open this URL in your browser to see the demo app"
  value       = "http://${aws_lb.main.dns_name}"
}

output "ec2_public_ip" {
  description = "EC2 instance public IP address"
  value       = aws_instance.k8s_host.public_ip
}

output "node_port" {
  description = "Kubernetes NodePort that the demo app listens on (EC2 host port)"
  value       = var.node_port
}

output "ec2_ssh_command" {
  description = "SSH command to connect to the EC2 instance for debugging"
  value       = "ssh -i ${path.module}/generated/ec2-key.pem ubuntu@${aws_instance.k8s_host.public_ip}"
  sensitive   = true
}

output "ami_id" {
  description = "Ubuntu AMI ID that was used for the EC2 instance"
  value       = data.aws_ami.ubuntu.id
}

output "kubeconfig_path" {
  description = "Local path to the kubeconfig file (fetched from EC2 after bootstrap)"
  value       = "${path.module}/generated/kubeconfig"
}
