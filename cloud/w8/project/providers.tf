# =============================================================================
# providers.tf — Terraform providers configuration
#
# Providers:
#   - AWS   : Infrastructure (EC2, VPC, SG, ALB, TG, Listener)
#   - Null  : Remote-exec provisioners (wait bootstrap, deploy K8s manifests)
#   - Local : Write generated files (private key) to local disk
#   - TLS   : Generate RSA key pair for EC2 SSH access
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

