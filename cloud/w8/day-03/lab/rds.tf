# =============================================================================
# rds.tf — RDS MySQL in Private Subnet
#
# Step 3: Deploy RDS MySQL in private subnet
#
# - Engine: MySQL 8.0
# - Placed in private subnets (no public access)
# - DB Subnet Group spans both private subnets (Multi-AZ ready)
# - Security Group allows inbound MySQL only from EC2 web server SG
# - Automated backups enabled (7-day retention)
# - Deletion protection disabled for lab (enable in production!)
# =============================================================================

# ── DB Subnet Group ────────────────────────────────────────────────────────────
# Must span at least 2 AZs for Multi-AZ support
resource "aws_db_subnet_group" "mysql" {
  name        = "${var.project_name}-db-subnet-group"
  description = "DB subnet group for ${var.project_name} MySQL - private subnets only"
  subnet_ids  = local.rds_subnet_ids

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# ── RDS MySQL Instance ─────────────────────────────────────────────────────────
resource "aws_db_instance" "mysql" {
  identifier = "${var.project_name}-mysql"

  # ── Engine ──────────────────────────────────────────────────────────────────
  engine               = "mysql"
  engine_version       = var.db_engine_version
  instance_class       = var.db_instance_class

  # ── Storage ─────────────────────────────────────────────────────────────────
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = 100 # Autoscaling ceiling (GB)
  storage_type          = "gp3"
  storage_encrypted     = true

  # ── Credentials ─────────────────────────────────────────────────────────────
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # ── Networking ──────────────────────────────────────────────────────────────
  db_subnet_group_name   = aws_db_subnet_group.mysql.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false # Private subnet, no public endpoint

  # ── High Availability ───────────────────────────────────────────────────────
  multi_az = var.db_multi_az

  # ── Backups ─────────────────────────────────────────────────────────────────
  backup_retention_period = 7
  backup_window           = "03:00-04:00"  # UTC - low traffic window

  # ── Maintenance ─────────────────────────────────────────────────────────────
  maintenance_window         = "Mon:04:00-Mon:05:00"
  auto_minor_version_upgrade = true

  # ── Snapshots & Deletion ────────────────────────────────────────────────────
  skip_final_snapshot       = true  # Change to false in production
  final_snapshot_identifier = "${var.project_name}-mysql-final-snapshot"
  deletion_protection       = false # Change to true in production

  # ── Monitoring ──────────────────────────────────────────────────────────────
  monitoring_interval = 0 # Set to 60 for Enhanced Monitoring in production
  enabled_cloudwatch_logs_exports = ["error", "general", "slowquery"]

  # ── Parameter Group (use default) ───────────────────────────────────────────
  # parameter_group_name = "default.mysql8.0"

  apply_immediately = true

  tags = {
    Name = "${var.project_name}-mysql"
    Role = "database"
  }
}
