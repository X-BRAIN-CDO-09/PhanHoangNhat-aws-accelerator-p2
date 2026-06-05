# =============================================================================
# providers.tf — Terraform providers configuration
#
# Providers:
#   - AWS      : Infrastructure (EC2, VPC, SG, ALB, TG, Listener)
#   - Null     : Remote-exec provisioners (wait bootstrap, deploy K8s manifests)
#   - Local    : Write generated files (kubeconfig) to local disk
#   - Kubernetes: K8s resources (Namespace, ConfigMap, Deployment, Service)
#               NOTE: Kubernetes provider connects via SSH port-forward.
#               If direct API access is not feasible, fallback to null_resource
#               remote-exec as documented in README.
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# ── AWS Provider ──────────────────────────────────────────────────────────────
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      ManagedBy   = "Terraform"
      Environment = "demo"
    }
  }
}

# ── Kubernetes Provider ───────────────────────────────────────────────────────
# LIMITATION: The kind API server runs on 127.0.0.1 inside EC2 and is NOT
# accessible publicly. This provider cannot connect directly.
#
# STRATEGY: All K8s resources are deployed via null_resource.deploy_k8s in
# bootstrap.tf using remote-exec (kubectl apply inside EC2 over SSH).
# This provider block is declared but no resources use it in the active config.
# Resources in kubernetes.tf are commented out for reference.
#
# To enable: set up SSH tunnel → update config_path kubeconfig server URL
# See README.md "SSH Tunnel (Advanced)" section.
provider "kubernetes" {
  config_path = "${path.module}/generated/kubeconfig"
}

