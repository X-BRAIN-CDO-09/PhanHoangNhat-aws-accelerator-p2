#!/bin/bash
# =============================================================================
# user_data.sh.tpl — EC2 Bootstrap Script (templatefile rendered by Terraform)
#
# This script runs as root on first boot via cloud-init.
# It installs:
#   - Nginx (reverse proxy / static file server)
#   - PHP 8.1 + PHP-FPM (application runtime)
#   - MySQL client (to test RDS connectivity)
#   - AWS CLI v2 (for S3 access)
#   - A simple PHP info page to verify the stack is working
#
# Template variables (replaced by Terraform templatefile()):
#   ${project_name}  — project prefix
#   ${db_host}       — RDS MySQL hostname
#   ${db_name}       — database name
#   ${db_username}   — database master username
#   ${db_password}   — database master password
#   ${s3_bucket}     — S3 bucket name for static assets
#   ${aws_region}    — AWS region
# =============================================================================

set -euxo pipefail
exec > >(tee /var/log/user_data.log | logger -t user_data -s 2>/dev/console) 2>&1

echo "========================================"
echo "  ${project_name} — EC2 Bootstrap Start"
echo "========================================"

# ── System Update ─────────────────────────────────────────────────────────────
dnf update -y

# ── Install Nginx ─────────────────────────────────────────────────────────────
dnf install -y nginx
systemctl enable nginx
systemctl start nginx

# ── Install PHP 8.1 + PHP-FPM + MySQL Extension ───────────────────────────────
dnf install -y \
  php8.1 \
  php8.1-fpm \
  php8.1-mysqlnd \
  php8.1-json \
  php8.1-mbstring \
  php8.1-xml \
  php8.1-curl

systemctl enable php-fpm
systemctl start php-fpm

# ── Install MySQL Client (for connectivity testing) ───────────────────────────
dnf install -y mysql

# ── Install AWS CLI v2 ────────────────────────────────────────────────────────
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
cd /tmp && unzip -q awscliv2.zip && ./aws/install
aws --version

# ── Configure Nginx for PHP-FPM ───────────────────────────────────────────────
cat > /etc/nginx/conf.d/webapp.conf << 'NGINX_CONF'
server {
    listen 80 default_server;
    server_name _;
    root /var/www/html;
    index index.php index.html;

    # Health check endpoint
    location /health {
        return 200 "OK\n";
        add_header Content-Type text/plain;
    }

    # Static files — serve directly
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff|woff2|ttf|svg)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
        try_files $uri =404;
    }

    # PHP processing
    location ~ \.php$ {
        fastcgi_pass  unix:/run/php-fpm/www.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include       fastcgi_params;
    }

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }
}
NGINX_CONF

# ── Create web root ───────────────────────────────────────────────────────────
mkdir -p /var/www/html
chown -R nginx:nginx /var/www/html

# ── Write application index page ──────────────────────────────────────────────
cat > /var/www/html/index.php << 'PHP_PAGE'
<?php
// ── Environment / Config ─────────────────────────────────────────────────────
$db_host     = getenv('DB_HOST')     ?: '${db_host}';
$db_name     = getenv('DB_NAME')     ?: '${db_name}';
$db_user     = getenv('DB_USERNAME') ?: '${db_username}';
$db_pass     = getenv('DB_PASSWORD') ?: '${db_password}';
$s3_bucket   = getenv('S3_BUCKET')   ?: '${s3_bucket}';
$aws_region  = getenv('AWS_REGION')  ?: '${aws_region}';

// ── Test RDS Connection ───────────────────────────────────────────────────────
$db_status  = '❌ Not Connected';
$db_error   = '';
try {
    $dsn = "mysql:host=$db_host;dbname=$db_name;charset=utf8mb4";
    $pdo = new PDO($dsn, $db_user, $db_pass, [PDO::ATTR_TIMEOUT => 5]);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    $db_status = '✅ Connected';
} catch (PDOException $e) {
    $db_error = htmlspecialchars($e->getMessage());
}
?>
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${project_name} — Web App on AWS</title>
<style>
  body { font-family: Arial, sans-serif; background: #0f172a; color: #e2e8f0; margin: 0; padding: 2rem; }
  .container { max-width: 900px; margin: 0 auto; }
  h1 { color: #38bdf8; border-bottom: 2px solid #334155; padding-bottom: 0.5rem; }
  .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 1rem; margin-top: 2rem; }
  .card { background: #1e293b; border-radius: 12px; padding: 1.5rem; border: 1px solid #334155; }
  .card h3 { margin-top: 0; color: #94a3b8; font-size: 0.85rem; text-transform: uppercase; letter-spacing: 0.05em; }
  .card p { margin: 0.25rem 0; font-size: 1rem; word-break: break-all; }
  .badge { display: inline-block; padding: 0.2rem 0.6rem; border-radius: 999px; font-size: 0.85rem; }
  .ok   { background: #14532d; color: #86efac; }
  .err  { background: #450a0a; color: #fca5a5; }
  footer { margin-top: 3rem; text-align: center; color: #475569; font-size: 0.8rem; }
</style>
</head>
<body>
<div class="container">
  <h1>🚀 ${project_name} — Web App on AWS</h1>
  <p>Infrastructure: <strong>VPC + EC2 + RDS MySQL + S3</strong> — managed by Terraform</p>

  <div class="grid">
    <div class="card">
      <h3>🖥️ EC2 Web Server</h3>
      <p>Instance ID: <?= htmlspecialchars(shell_exec('curl -sf http://169.254.169.254/latest/meta-data/instance-id') ?: 'n/a') ?></p>
      <p>Public IP: <?= htmlspecialchars(shell_exec('curl -sf http://169.254.169.254/latest/meta-data/public-ipv4') ?: 'n/a') ?></p>
      <p>AZ: <?= htmlspecialchars(shell_exec('curl -sf http://169.254.169.254/latest/meta-data/placement/availability-zone') ?: 'n/a') ?></p>
      <p>PHP: <?= PHP_VERSION ?></p>
    </div>

    <div class="card">
      <h3>🗄️ RDS MySQL</h3>
      <p>Host: <?= htmlspecialchars($db_host) ?></p>
      <p>Database: <?= htmlspecialchars($db_name) ?></p>
      <p>Status: <span class="badge <?= $db_error ? 'err' : 'ok' ?>"><?= $db_status ?></span></p>
      <?php if ($db_error): ?>
      <p style="color:#f87171;font-size:0.8rem;"><?= $db_error ?></p>
      <?php endif; ?>
    </div>

    <div class="card">
      <h3>🪣 S3 Static Assets</h3>
      <p>Bucket: <?= htmlspecialchars($s3_bucket) ?></p>
      <p>Region: <?= htmlspecialchars($aws_region) ?></p>
      <p>Status: <span class="badge ok">✅ Configured</span></p>
    </div>
  </div>

  <footer>Deployed with Terraform · Week 8 Day 3 Lab · <?= date('Y-m-d H:i:s T') ?></footer>
</div>
</body>
</html>
PHP_PAGE

# ── Write environment config for the PHP app ──────────────────────────────────
cat > /var/www/html/.env << 'ENV_FILE'
DB_HOST=${db_host}
DB_NAME=${db_name}
DB_USERNAME=${db_username}
DB_PASSWORD=${db_password}
S3_BUCKET=${s3_bucket}
AWS_REGION=${aws_region}
ENV_FILE

# Secure the .env file
chmod 640 /var/www/html/.env
chown nginx:nginx /var/www/html/.env

# ── Deny access to .env via Nginx ─────────────────────────────────────────────
cat >> /etc/nginx/conf.d/webapp.conf << 'NGINX_DENY'

# Security: block access to .env and hidden files
location ~ /\. {
    deny all;
}
NGINX_DENY

# ── Nginx config test & restart ───────────────────────────────────────────────
nginx -t
systemctl reload nginx

# ── Upload a sample static asset to S3 ───────────────────────────────────────
cat > /tmp/sample_asset.html << 'SAMPLE'
<h1>Hello from S3!</h1>
<p>This file is served from the S3 static assets bucket.</p>
SAMPLE

aws s3 cp /tmp/sample_asset.html "s3://${s3_bucket}/assets/sample.html" \
  --region "${aws_region}" \
  --content-type "text/html" || echo "Warning: S3 upload failed — check IAM role"

echo "========================================"
echo "  ${project_name} — Bootstrap Complete!"
echo "  Nginx:   $(systemctl is-active nginx)"
echo "  PHP-FPM: $(systemctl is-active php-fpm)"
echo "========================================"
