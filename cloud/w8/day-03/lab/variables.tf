# =============================================================================
# variables.tf — Input Variables
#
# All configurable values are defined here. Override them in terraform.tfvars.
# =============================================================================

# ── General ───────────────────────────────────────────────────────────────────
variable "aws_region" {
  description = "AWS region to deploy all resources into"
  type        = string
  default     = "ap-southeast-1"
}

variable "project_name" {
  description = "Short project name used as a prefix for all resource names"
  type        = string
  default     = "webapp"
}

variable "environment" {
  description = "Deployment environment (dev / staging / prod)"
  type        = string
  default     = "dev"
}

# ── VPC / Networking ──────────────────────────────────────────────────────────
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the public subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
}

# ── EC2 ───────────────────────────────────────────────────────────────────────
variable "instance_type" {
  description = "EC2 instance type for the web server"
  type        = string
  default     = "t3.micro"
}

variable "allowed_ssh_cidr" {
  description = <<-EOT
    CIDR block allowed to SSH into the EC2 web server (port 22).
    Example: "203.0.113.42/32" — replace with your real public IP.
    DO NOT use 0.0.0.0/0 in production.
  EOT
  type        = string
  default     = "0.0.0.0/0" # CHANGE THIS before applying!

  validation {
    condition     = can(cidrnetmask(var.allowed_ssh_cidr))
    error_message = "allowed_ssh_cidr must be a valid CIDR block (e.g., '1.2.3.4/32')."
  }
}

# ── RDS MySQL ─────────────────────────────────────────────────────────────────
variable "db_name" {
  description = "Name of the MySQL database to create"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for the RDS MySQL instance"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "db_password" {
  description = "Master password for the RDS MySQL instance (min 8 chars)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "db_password must be at least 8 characters long."
  }
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage in GB for the RDS instance"
  type        = number
  default     = 20
}

variable "db_engine_version" {
  description = "MySQL engine version"
  type        = string
  default     = "8.0"
}

variable "db_multi_az" {
  description = "Enable Multi-AZ deployment for RDS (recommended for production)"
  type        = bool
  default     = false
}

# ── S3 ────────────────────────────────────────────────────────────────────────
variable "s3_bucket_name" {
  description = <<-EOT
    Globally unique S3 bucket name for static assets.
    Leave empty to auto-generate a name using project_name + random suffix.
  EOT
  type        = string
  default     = ""
}

variable "s3_force_destroy" {
  description = "Allow Terraform to destroy the S3 bucket even if it contains objects"
  type        = bool
  default     = true
}

# ── Bootstrap S3 Backend (run separately before terraform init) ───────────────
variable "backend_bucket_name" {
  description = "Name of the S3 bucket used for Terraform state storage (created by bootstrap)"
  type        = string
  default     = ""
}

variable "backend_dynamodb_table" {
  description = "Name of the DynamoDB table used for Terraform state locking (created by bootstrap)"
  type        = string
  default     = ""
}
