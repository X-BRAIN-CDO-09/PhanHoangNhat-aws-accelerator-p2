# 01 — AWS Secrets Manager

> **Scope:** Architecture, rotation, IAM policy, Terraform, pricing

---

## 1. AWS Secrets Manager là gì?

**AWS Secrets Manager** = managed service lưu trữ và tự động rotate credentials (DB passwords, API keys, tokens).

```
┌─────────────────────────────────────────────────┐
│              AWS Secrets Manager                  │
│                                                    │
│  ┌──────────────┐      ┌───────────────────┐      │
│  │   Secret     │      │  Rotation Lambda  │      │
│  │  (encrypted  │◄────►│  (auto-rotate)    │      │
│  │   via KMS)   │      │                   │      │
│  └──────┬───────┘      └───────────────────┘      │
│         │                                          │
│         │  GetSecretValue API                      │
│         ▼                                          │
│  ┌──────────────────────────────────────────┐     │
│  │  Consumers:                               │     │
│  │  • EKS pods (via ESO)                    │     │
│  │  • Lambda functions                       │     │
│  │  • EC2 instances (via SDK)               │     │
│  │  • ECS tasks                              │     │
│  └──────────────────────────────────────────┘     │
└─────────────────────────────────────────────────┘
```

### Secrets Manager vs Systems Manager Parameter Store

| Feature | Secrets Manager | Parameter Store |
|---|---|---|
| **Auto rotation** | ✅ Built-in | ❌ Manual |
| **Cross-account** | ✅ Resource policy | ⚠️ Limited |
| **Encryption** | KMS (mandatory) | KMS (optional) |
| **Versioning** | ✅ Staging labels | ✅ |
| **Pricing** | $0.40/secret/month + $0.05/10K API calls | Free tier (standard) |
| **Max size** | 64 KB | 8 KB (standard), 8 KB (advanced) |
| **Use case** | DB creds, API keys, certificates | Config values, feature flags |

---

## 2. Tạo Secret

### AWS CLI

```bash
# Tạo secret
aws secretsmanager create-secret \
  --name "production/myapp/database" \
  --description "Production database credentials" \
  --secret-string '{"username":"admin","password":"S3cur3P@ss!","host":"prod-db.cluster-xxx.ap-southeast-1.rds.amazonaws.com","port":"5432","dbname":"myapp"}' \
  --tags '[{"Key":"Environment","Value":"production"},{"Key":"Team","Value":"platform"}]'

# Đọc secret
aws secretsmanager get-secret-value \
  --secret-id "production/myapp/database" \
  --query 'SecretString' --output text | jq .

# Update secret value
aws secretsmanager put-secret-value \
  --secret-id "production/myapp/database" \
  --secret-string '{"username":"admin","password":"N3wP@ss!","host":"prod-db.cluster-xxx.ap-southeast-1.rds.amazonaws.com","port":"5432","dbname":"myapp"}'
```

### Terraform

```hcl
# secrets-manager.tf

# Tạo secret
resource "aws_secretsmanager_secret" "db_creds" {
  name        = "${var.environment}/myapp/database"
  description = "Database credentials for myapp"
  
  # KMS key cho encryption
  kms_key_id = aws_kms_key.secrets.arn
  
  # Recovery window — số ngày trước khi xoá vĩnh viễn
  recovery_window_in_days = 7
  
  tags = {
    Environment = var.environment
    Team        = "platform"
    ManagedBy   = "terraform"
  }
}

# Set initial value (KHÔNG nên lưu password trong Terraform state)
resource "aws_secretsmanager_secret_version" "db_creds" {
  secret_id = aws_secretsmanager_secret.db_creds.id
  secret_string = jsonencode({
    username = "admin"
    password = var.db_password    # Từ Terraform variable, không hardcode
    host     = aws_rds_cluster.main.endpoint
    port     = "5432"
    dbname   = "myapp"
  })
}

# KMS key cho secrets encryption
resource "aws_kms_key" "secrets" {
  description             = "KMS key for Secrets Manager"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  
  tags = {
    Purpose = "secrets-encryption"
  }
}
```

---

## 3. Automatic Rotation

### Tại sao cần rotation?

```
Không rotation:
  Password bị leak → kẻ tấn công dùng mãi → damage kéo dài

Có rotation (30 ngày):
  Password bị leak → tối đa 30 ngày → auto-rotate → kẻ tấn công bị lock out
```

### Cấu hình rotation cho RDS

```hcl
# rotation.tf

# Lambda rotation function (AWS managed cho RDS)
resource "aws_secretsmanager_secret_rotation" "db_creds" {
  secret_id           = aws_secretsmanager_secret.db_creds.id
  rotation_lambda_arn = aws_lambda_function.rotation.arn
  
  rotation_rules {
    automatically_after_days = 30    # Rotate mỗi 30 ngày
    # schedule_expression = "rate(30 days)"   # Alternative syntax
  }
}

# Dùng AWS Serverless Application Repository cho rotation Lambda
# https://docs.aws.amazon.com/secretsmanager/latest/userguide/reference_available-rotation-templates.html
```

### Rotation Steps (4-step process)

```
Step 1: createSecret
    │  • Tạo new password version với staging label AWSPENDING
    │
Step 2: setSecret  
    │  • Update database với password mới
    │
Step 3: testSecret
    │  • Verify kết nối DB bằng password mới
    │
Step 4: finishSecret
    │  • Chuyển staging label: AWSPENDING → AWSCURRENT
    │  • Password cũ: AWSCURRENT → AWSPREVIOUS
```

### Multi-user rotation strategy

```
Single-user rotation:       Multi-user rotation:
┌────────────────┐          ┌────────────────────────┐
│ Một user duy   │          │ 2 users luân phiên:    │
│ nhất. Khi      │          │                        │
│ rotate = có    │          │ user_A (AWSCURRENT)    │
│ downtime ngắn  │          │ user_B (chờ rotate)    │
│ (1-2 giây)     │          │                        │
└────────────────┘          │ Rotate: B lên CURRENT  │
                            │ A được đổi password    │
                            │ → Zero downtime        │
                            └────────────────────────┘
```

---

## 4. IAM Policy — Least Privilege Access

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowReadSpecificSecret",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:ap-southeast-1:123456789012:secret:production/myapp/*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "ap-southeast-1"
        }
      }
    },
    {
      "Sid": "AllowDecryptWithKMS",
      "Effect": "Allow",
      "Action": "kms:Decrypt",
      "Resource": "arn:aws:kms:ap-southeast-1:123456789012:key/xxx-yyy-zzz",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": "secretsmanager.ap-southeast-1.amazonaws.com"
        }
      }
    }
  ]
}
```

### IAM Policy for EKS (IRSA)

```hcl
# Cho ESO ServiceAccount đọc secrets
resource "aws_iam_role" "eso" {
  name = "eso-secrets-reader"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${aws_iam_openid_connect_provider.eks.url}:sub" = 
            "system:serviceaccount:external-secrets:external-secrets"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "eso_secrets" {
  role = aws_iam_role.eso.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
      Resource = "arn:aws:secretsmanager:ap-southeast-1:123456789012:secret:${var.environment}/*"
    }]
  })
}
```

---

## 5. Naming Convention

```
<environment>/<application>/<secret-type>

Ví dụ:
  production/myapp/database
  production/myapp/api-keys
  staging/myapp/database
  shared/infrastructure/datadog-api-key
```

---

## 6. Pricing

| Item | Cost |
|---|---|
| Storage | $0.40 / secret / month |
| API calls | $0.05 / 10,000 calls |
| Rotation Lambda | Lambda pricing (thường negligible) |

> **Tip:** Dùng 1 secret chứa JSON object thay vì nhiều secrets riêng → giảm cost.
>
> ```json
> // 1 secret = $0.40/month thay vì 4 secrets = $1.60/month
> {
>   "db_username": "admin",
>   "db_password": "xxx",
>   "redis_password": "yyy",
>   "api_key": "zzz"
> }
> ```
