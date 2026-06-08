# =============================================================================
# s3.tf — S3 Bucket for Static Assets
#
# Step 4: Create S3 bucket for static assets
#
# Features:
#   - Versioning enabled
#   - Server-side encryption (AES-256)
#   - Public access blocked (serve via CloudFront or EC2 presigned URLs)
#   - Lifecycle rules for cost optimization
#   - CORS configuration for web app usage
# =============================================================================

# ── Random suffix to ensure globally unique bucket name ───────────────────────
resource "random_id" "bucket_suffix" {
  byte_length = 4
}

locals {
  # Use user-supplied name or generate one automatically
  s3_bucket_name = var.s3_bucket_name != "" ? var.s3_bucket_name : "${var.project_name}-static-assets-${random_id.bucket_suffix.hex}"
}

# ── S3 Bucket ─────────────────────────────────────────────────────────────────
resource "aws_s3_bucket" "static_assets" {
  bucket        = local.s3_bucket_name
  force_destroy = var.s3_force_destroy

  tags = {
    Name    = local.s3_bucket_name
    Purpose = "static-assets"
  }
}

# ── Versioning ─────────────────────────────────────────────────────────────────
resource "aws_s3_bucket_versioning" "static_assets" {
  bucket = aws_s3_bucket.static_assets.id

  versioning_configuration {
    status = "Enabled"
  }
}

# ── Server-Side Encryption ─────────────────────────────────────────────────────
resource "aws_s3_bucket_server_side_encryption_configuration" "static_assets" {
  bucket = aws_s3_bucket.static_assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# ── Block All Public Access ────────────────────────────────────────────────────
# Assets are served through EC2 (presigned URLs) or CloudFront — NOT directly public
resource "aws_s3_bucket_public_access_block" "static_assets" {
  bucket = aws_s3_bucket.static_assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── CORS Configuration ────────────────────────────────────────────────────────
resource "aws_s3_bucket_cors_configuration" "static_assets" {
  bucket = aws_s3_bucket.static_assets.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD", "PUT", "POST"]
    allowed_origins = ["*"] # Restrict to your domain in production
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}

# ── Lifecycle Rules ───────────────────────────────────────────────────────────
resource "aws_s3_bucket_lifecycle_configuration" "static_assets" {
  bucket = aws_s3_bucket.static_assets.id

  # Move non-current versions to cheaper storage after 30 days, expire after 90
  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {} # Required by AWS provider v5 (empty = apply to all objects)

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  # Move old objects to IA after 60 days, Glacier after 180 days
  rule {
    id     = "archive-old-objects"
    status = "Enabled"

    filter {} # Required by AWS provider v5 (empty = apply to all objects)

    transition {
      days          = 60
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 180
      storage_class = "GLACIER"
    }
  }
}

# ── Bucket Policy: Allow EC2 IAM Role to Access the Bucket ───────────────────
resource "aws_s3_bucket_policy" "static_assets" {
  bucket = aws_s3_bucket.static_assets.id
  policy = data.aws_iam_policy_document.s3_access.json

  depends_on = [aws_s3_bucket_public_access_block.static_assets]
}

data "aws_iam_policy_document" "s3_access" {
  # Allow EC2 instance role to read/write objects
  statement {
    sid    = "AllowEC2RoleAccess"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.ec2_s3_role.arn]
    }

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket"
    ]

    resources = [
      aws_s3_bucket.static_assets.arn,
      "${aws_s3_bucket.static_assets.arn}/*"
    ]
  }

  # Enforce HTTPS only
  statement {
    sid    = "DenyNonHTTPS"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.static_assets.arn,
      "${aws_s3_bucket.static_assets.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

# ── IAM Role for EC2 to Access S3 ────────────────────────────────────────────
resource "aws_iam_role" "ec2_s3_role" {
  name = "${var.project_name}-ec2-s3-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-ec2-s3-role"
  }
}

resource "aws_iam_role_policy" "ec2_s3_policy" {
  name = "${var.project_name}-ec2-s3-policy"
  role = aws_iam_role.ec2_s3_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.static_assets.arn,
          "${aws_s3_bucket.static_assets.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2_s3_profile" {
  name = "${var.project_name}-ec2-s3-profile"
  role = aws_iam_role.ec2_s3_role.name

  tags = {
    Name = "${var.project_name}-ec2-s3-profile"
  }
}
