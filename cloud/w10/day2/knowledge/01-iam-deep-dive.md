# IAM Deep Dive — Policy, Role, Least Privilege

> **Nguồn:** W10-D2 | **Chủ đề:** IAM (Identity and Access Management)

---

## 1. IAM Policy — Cấu trúc

Mỗi IAM Policy là một JSON document định nghĩa **ai** có thể làm **gì** trên **resource nào**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3ReadOnly",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::my-app-bucket",
        "arn:aws:s3:::my-app-bucket/*"
      ],
      "Condition": {
        "IpAddress": {
          "aws:SourceIp": "10.0.0.0/8"
        }
      }
    }
  ]
}
```

### Các thành phần:

| Thành phần | Mô tả | Ví dụ |
|---|---|---|
| **Effect** | Allow hoặc Deny | `"Allow"` |
| **Action** | API actions | `"s3:GetObject"`, `"ec2:*"` |
| **Resource** | ARN của resource | `"arn:aws:s3:::my-bucket/*"` |
| **Condition** | Điều kiện bổ sung | IP range, MFA required, time |
| **Sid** | Statement ID (optional) | `"AllowS3ReadOnly"` |

### Policy Evaluation Logic

```
     ┌─────────────────┐
     │  Có Explicit     │
     │  DENY?           │
     │                  │
     └────┬────────┬────┘
          │YES     │NO
          ▼        ▼
     ┌────────┐ ┌─────────────────┐
     │ DENY   │ │  Có Explicit     │
     │        │ │  ALLOW?          │
     └────────┘ └────┬────────┬────┘
                     │YES     │NO
                     ▼        ▼
                ┌────────┐ ┌────────┐
                │ ALLOW  │ │ DENY   │
                │        │ │(implicit│
                └────────┘ └────────┘
```

> **Rule:** Explicit Deny > Explicit Allow > Implicit Deny (default)

---

## 2. Least Privilege Principle

### ❌ Bad — Quá rộng

```json
{
  "Effect": "Allow",
  "Action": "*",
  "Resource": "*"
}
```

### ✅ Good — Chỉ cho phép đủ quyền

```json
{
  "Effect": "Allow",
  "Action": [
    "s3:GetObject",
    "s3:PutObject"
  ],
  "Resource": "arn:aws:s3:::my-app-bucket/uploads/*"
}
```

### Workflow áp dụng Least Privilege:

```
1. Bắt đầu với ZERO permissions
2. Xác định chính xác actions cần thiết
3. Giới hạn resource (không dùng *)
4. Thêm conditions nếu có thể
5. Test với IAM Policy Simulator
6. Monitor với CloudTrail → phát hiện unused permissions
7. Định kỳ review và remove unused permissions
```

---

## 3. IAM Role vs IAM User

| Tiêu chí | IAM User | IAM Role |
|---|---|---|
| **Credentials** | Long-term (password + access key) | Temporary (STS token) |
| **Dùng cho** | Người thật (console login) | Services, applications |
| **Rotate** | Phải tự rotate access keys | Tự động rotate |
| **Cross-account** | Không | Có (assume role) |
| **Security** | Rủi ro leak credentials | An toàn hơn |

### Khi nào dùng gì?

```
IAM User:
  ✅ Con người cần login AWS Console
  ✅ CI/CD pipeline (nếu không thể dùng OIDC)
  ⚠️ Luôn enable MFA
  ⚠️ Rotate access keys 90 ngày

IAM Role:
  ✅ EC2 instances (Instance Profile)
  ✅ Lambda functions (Execution Role)
  ✅ ECS tasks (Task Role)
  ✅ Cross-account access
  ✅ CI/CD với OIDC (GitHub Actions)
  → MỌI service nên dùng Role, KHÔNG User
```

---

## 4. IAM Role cho EC2 — Instance Profile

EC2 không dùng access keys mà nhận credentials qua **Instance Profile**:

```
EC2 Instance
    │
    ├── Instance Profile ← container cho IAM Role
    │       │
    │       └── IAM Role
    │             │
    │             └── IAM Policy (permissions)
    │
    └── Application code
          │
          └── boto3/SDK tự động lấy credentials
              từ Instance Metadata Service (IMDS)
```

### Terraform

```hcl
# 1. Tạo IAM Role
resource "aws_iam_role" "ec2_app" {
  name = "ec2-app-role-${var.environment}"
  
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
}

# 2. Attach policy (ví dụ: S3 read-only)
resource "aws_iam_role_policy" "s3_read" {
  name = "s3-read-policy"
  role = aws_iam_role.ec2_app.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.app.arn,
          "${aws_s3_bucket.app.arn}/*"
        ]
      }
    ]
  })
}

# 3. Tạo Instance Profile
resource "aws_iam_instance_profile" "ec2_app" {
  name = "ec2-app-profile-${var.environment}"
  role = aws_iam_role.ec2_app.name
}

# 4. Gắn vào EC2
resource "aws_instance" "app" {
  ami                  = data.aws_ami.amazon_linux.id
  instance_type        = "t3.micro"
  iam_instance_profile = aws_iam_instance_profile.ec2_app.name
  # ...
}
```

---

## 5. IAM Role cho Lambda — Execution Role

```hcl
resource "aws_iam_role" "lambda_exec" {
  name = "lambda-exec-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

# Cho phép Lambda ghi CloudWatch Logs
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Thêm custom permission (ví dụ: DynamoDB)
resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "lambda-dynamodb-access"
  role = aws_iam_role.lambda_exec.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query"
        ]
        Resource = aws_dynamodb_table.orders.arn
      }
    ]
  })
}
```

---

## 6. IAM Policy Simulator

Dùng **IAM Policy Simulator** để test policy TRƯỚC khi deploy:

```
URL: https://policysim.aws.amazon.com/

Workflow:
1. Chọn User/Role
2. Chọn Service + Action
3. Specify Resource ARN
4. Run Simulation
5. Xem kết quả: Allowed / Denied + lý do
```

### CLI test:

```bash
# Test xem user có quyền s3:GetObject không
aws iam simulate-principal-policy \
  --policy-source-arn "arn:aws:iam::123456789:user/developer" \
  --action-names "s3:GetObject" \
  --resource-arns "arn:aws:s3:::my-bucket/file.txt"
```

---

## 7. Common IAM Patterns

### Pattern 1: Tag-based Access Control

```json
{
  "Effect": "Allow",
  "Action": "ec2:*",
  "Resource": "*",
  "Condition": {
    "StringEquals": {
      "ec2:ResourceTag/Environment": "${aws:PrincipalTag/Environment}"
    }
  }
}
```

> Dev chỉ quản lý EC2 có tag `Environment=dev`, Prod team quản lý `Environment=prod`.

### Pattern 2: MFA Required

```json
{
  "Effect": "Deny",
  "Action": "*",
  "Resource": "*",
  "Condition": {
    "BoolIfExists": {
      "aws:MultiFactorAuthPresent": "false"
    }
  }
}
```

### Pattern 3: IP Restriction

```json
{
  "Effect": "Deny",
  "Action": "*",
  "Resource": "*",
  "Condition": {
    "NotIpAddress": {
      "aws:SourceIp": ["10.0.0.0/8", "172.16.0.0/12"]
    }
  }
}
```

---

## 🔗 Tài liệu tham khảo

- [IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html) ⭐⭐⭐
- [IAM Policy Evaluation Logic](https://docs.aws.amazon.com/IAM/latest/UserGuide/reference_policies_evaluation-logic.html) ⭐⭐⭐
- [IAM Policy Simulator](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_testing-policies.html) ⭐⭐
