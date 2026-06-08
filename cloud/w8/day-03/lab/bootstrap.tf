# =============================================================================
# bootstrap.tf — Create S3 Backend and DynamoDB Lock Table
#
# PURPOSE: This file creates the S3 bucket and DynamoDB table required for
# the Terraform remote state backend BEFORE you can use the backend.
#
# WORKFLOW:
#   Phase 1 — Bootstrap (comment out the backend block in providers.tf):
#     terraform init
#     terraform apply -target=aws_s3_bucket.tfstate -target=aws_dynamodb_table.tfstate_lock
#
#   Phase 2 — Migrate state to S3 backend:
#     1. Update providers.tf backend block with actual bucket/table names
#     2. Run: terraform init -migrate-state
#     3. Confirm "yes" when prompted
#
#   Phase 3 — Normal operations:
#     terraform plan / apply (state is now in S3)
#
# NOTE: Delete this file or move its resources to a separate folder if you
#       want to manage the backend resources separately.
# =============================================================================

# ── Random suffix for globally unique S3 bucket name ─────────────────────────
resource "random_id" "tfstate_suffix" {
  byte_length = 4
}

locals {
  tfstate_bucket_name = "${var.project_name}-tfstate-${var.aws_region}-${random_id.tfstate_suffix.hex}"
  dynamodb_table_name = "${var.project_name}-tfstate-lock"
}

# ── S3 Bucket for Terraform State ─────────────────────────────────────────────
resource "aws_s3_bucket" "tfstate" {
  bucket        = local.tfstate_bucket_name
  force_destroy = false # Protect state from accidental deletion

  tags = {
    Name    = local.tfstate_bucket_name
    Purpose = "terraform-state"
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled" # Required — allows state rollback
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── DynamoDB Table for State Locking ──────────────────────────────────────────
# Partition key MUST be "LockID" (String) — this is what Terraform expects
resource "aws_dynamodb_table" "tfstate_lock" {
  name         = local.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST" # No capacity planning needed for locking
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  tags = {
    Name    = local.dynamodb_table_name
    Purpose = "terraform-state-lock"
  }
}

# ── Outputs: Copy these values into providers.tf backend block ────────────────
output "tfstate_bucket_name" {
  description = "S3 bucket name for Terraform state — use in providers.tf backend block"
  value       = aws_s3_bucket.tfstate.id
}

output "tfstate_dynamodb_table" {
  description = "DynamoDB table name for state locking — use in providers.tf backend block"
  value       = aws_dynamodb_table.tfstate_lock.name
}

output "backend_config_snippet" {
  description = "Copy-paste this into the backend block in providers.tf"
  value       = <<-EOT
    backend "s3" {
      bucket         = "${aws_s3_bucket.tfstate.id}"
      key            = "w8/day-03/lab/terraform.tfstate"
      region         = "${var.aws_region}"
      dynamodb_table = "${aws_dynamodb_table.tfstate_lock.name}"
      encrypt        = true
    }
  EOT
}
