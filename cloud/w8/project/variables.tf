# =============================================================================
# variables.tf — Input variables for the Terraform project
# =============================================================================

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Project name used as a prefix for all resource names"
  type        = string
  default     = "k8s-demo"
}

variable "instance_type" {
  description = <<-EOT
    EC2 instance type for the Kubernetes host.
    Minimum recommended: t3.medium (2 vCPU, 4 GB RAM) for kind to run comfortably.
  EOT
  type        = string
  default     = "t3.medium"
}


variable "allowed_ssh_cidr" {
  description = <<-EOT
    CIDR block allowed to SSH into the EC2 instance (port 22).
    Example: "203.0.113.42/32" for a single IP.
    Do NOT use 0.0.0.0/0 in production — restrict to your actual IP.
  EOT
  type        = string

  validation {
    condition     = can(cidrnetmask(var.allowed_ssh_cidr))
    error_message = "allowed_ssh_cidr must be a valid CIDR block (e.g., '1.2.3.4/32')."
  }
}

variable "node_port" {
  description = "Kubernetes NodePort that the nginx Service will listen on (and ALB will forward to)"
  type        = number
  default     = 30080

  validation {
    condition     = var.node_port >= 30000 && var.node_port <= 32767
    error_message = "node_port must be in the Kubernetes NodePort range: 30000-32767."
  }
}

variable "cluster_name" {
  description = "Name for the kind Kubernetes cluster"
  type        = string
  default     = "demo-cluster"
}
