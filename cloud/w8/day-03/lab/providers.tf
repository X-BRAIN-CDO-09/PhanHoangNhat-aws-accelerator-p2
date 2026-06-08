# =============================================================================
# providers.tf — Terraform & Provider Configuration
#
# Backend  : S3 remote state with DynamoDB locking
# Providers: AWS (main infrastructure)
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }

  # --------------------------------------------------------------------------
  # Remote State Backend — S3 + DynamoDB
  # --------------------------------------------------------------------------
  # BEFORE FIRST USE:
  #   1. Create the S3 bucket (versioning enabled, server-side encryption)
  #   2. Create the DynamoDB table (partition key = "LockID", type String)
  #   3. Update the bucket name and table name below
  #   Run: terraform init -reconfigure
  # --------------------------------------------------------------------------
  backend "s3" {
    bucket         = "s3-terraform-remote-lab" # e.g. "myproject-tfstate-ap-southeast-1"
    key            = "w8/day-03/lab/terraform.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "dynamo-terraform-remote-lab"  # e.g. "myproject-tfstate-lock"
    encrypt        = true
  }
}

# ── AWS Provider ──────────────────────────────────────────────────────────────
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Week        = "W8-Day03"
    }
  }
}
