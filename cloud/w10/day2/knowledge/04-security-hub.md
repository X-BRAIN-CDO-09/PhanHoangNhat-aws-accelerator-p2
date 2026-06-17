# Security Hub — Aggregate Findings & Compliance

> **Nguồn:** W10-D2 | **Chủ đề:** AWS Security Hub

---

## 1. Security Hub là gì?

**Security Hub** là central dashboard để **aggregate, organize, và prioritize** security findings từ nhiều AWS services và 3rd party tools.

```
     ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
     │  GuardDuty   │  │  Inspector   │  │  Macie       │
     │  (Threats)   │  │  (Vuln scan) │  │  (S3 data)   │
     └──────┬───────┘  └──────┬───────┘  └──────┬───────┘
            │                 │                  │
            ▼                 ▼                  ▼
     ┌─────────────────────────────────────────────────┐
     │              AWS Security Hub                    │
     │                                                  │
     │  ┌──────────────────────────────────────────┐   │
     │  │  Findings (normalized to ASFF format)     │   │
     │  └──────────────────────────────────────────┘   │
     │                                                  │
     │  ┌──────────────────────────────────────────┐   │
     │  │  Security Standards & Compliance Checks  │   │
     │  │  • CIS AWS Foundations Benchmark         │   │
     │  │  • AWS Foundational Security Best Pracs  │   │
     │  │  • PCI DSS                               │   │
     │  └──────────────────────────────────────────┘   │
     │                                                  │
     │  Security Score: 85/100                         │
     └─────────────────────────────────────────────────┘
```

### Key features:

- **Centralized view** — tất cả findings ở 1 nơi
- **ASFF format** — AWS Security Finding Format (chuẩn hoá)
- **Compliance checks** — tự động check theo security standards
- **Security Score** — điểm tổng hợp (0-100)
- **Automated actions** — EventBridge integration

---

## 2. Security Standards

### CIS AWS Foundations Benchmark

**CIS (Center for Internet Security)** — bộ tiêu chuẩn security được industry công nhận:

| Category | Ví dụ Controls |
|---|---|
| **IAM** | Root account không dùng access key, MFA enabled |
| **Logging** | CloudTrail enabled all regions, log file validation |
| **Monitoring** | CloudWatch alarms cho unauthorized API calls |
| **Networking** | No security groups allow 0.0.0.0/0 to port 22 |
| **Storage** | S3 buckets không public |

### AWS Foundational Security Best Practices (FSBP)

AWS tự maintain — cover nhiều services hơn CIS:

```
FSBP Controls examples:
  ✅ EC2.8  — IMDSv2 should be required
  ✅ IAM.4  — IAM root user access key should not exist
  ✅ S3.1   — S3 Block Public Access enabled
  ✅ RDS.3  — RDS instances should have encryption at rest
  ✅ Lambda.1 — Lambda functions should not have public access
```

### PCI DSS

Cho workloads xử lý payment card data.

---

## 3. Enable Security Hub bằng Terraform

```hcl
# security-hub.tf

# Enable Security Hub
resource "aws_securityhub_account" "main" {}

# Enable CIS AWS Foundations Benchmark
resource "aws_securityhub_standards_subscription" "cis" {
  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.4.0"
}

# Enable AWS Foundational Security Best Practices
resource "aws_securityhub_standards_subscription" "aws_fsbp" {
  depends_on    = [aws_securityhub_account.main]
  standards_arn = "arn:aws:securityhub:${var.region}::standards/aws-foundational-security-best-practices/v/1.0.0"
}
```

### Tích hợp với GuardDuty:

```hcl
# GuardDuty findings tự động xuất hiện trong Security Hub
# (nếu cả hai đều enabled trong cùng region)

# Nhưng cần explicit enable member:
resource "aws_securityhub_product_subscription" "guardduty" {
  depends_on  = [aws_securityhub_account.main]
  product_arn = "arn:aws:securityhub:${var.region}::product/aws/guardduty"
}

resource "aws_securityhub_product_subscription" "inspector" {
  depends_on  = [aws_securityhub_account.main]
  product_arn = "arn:aws:securityhub:${var.region}::product/aws/inspector"
}
```

---

## 4. ASFF — AWS Security Finding Format

Tất cả findings được normalize thành format chuẩn:

```json
{
  "SchemaVersion": "2018-10-08",
  "Id": "arn:aws:securityhub:ap-southeast-1:123456789:finding/...",
  "ProductArn": "arn:aws:securityhub:ap-southeast-1::product/aws/guardduty",
  "GeneratorId": "arn:aws:guardduty:ap-southeast-1:123456789:detector/...",
  "AwsAccountId": "123456789",
  "Types": ["TTPs/UnauthorizedAccess"],
  "CreatedAt": "2026-06-17T10:30:00.000Z",
  "Severity": {
    "Label": "HIGH",
    "Normalized": 70
  },
  "Title": "SSH brute force attack on EC2 instance",
  "Description": "...",
  "Resources": [
    {
      "Type": "AwsEc2Instance",
      "Id": "arn:aws:ec2:ap-southeast-1:123456789:instance/i-0123456789",
      "Region": "ap-southeast-1"
    }
  ],
  "Compliance": {
    "Status": "FAILED"
  },
  "Workflow": {
    "Status": "NEW"
  }
}
```

### Finding Lifecycle:

```
NEW → NOTIFIED → RESOLVED → SUPPRESSED
  │       │          │           │
  │       │          │           └── False positive, excluded
  │       │          └── Issue fixed
  │       └── Team đã được thông báo
  └── Mới phát hiện
```

---

## 5. Automation với EventBridge

```hcl
# Auto-remediate: tự động isolate EC2 khi có critical finding
resource "aws_cloudwatch_event_rule" "critical_findings" {
  name = "securityhub-critical-findings"
  
  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = ["CRITICAL"]
        }
        Workflow = {
          Status = ["NEW"]
        }
      }
    }
  })
}

# Route to Lambda for auto-remediation
resource "aws_cloudwatch_event_target" "auto_remediate" {
  rule      = aws_cloudwatch_event_rule.critical_findings.name
  target_id = "auto-remediate"
  arn       = aws_lambda_function.auto_remediate.arn
}
```

---

## 6. Security Hub Dashboard — Đọc hiểu

```
Security Hub Console:
  ┌─────────────────────────────────────────┐
  │  Security Score: 85/100                 │
  │                                         │
  │  ┌─────────┐ ┌─────────┐ ┌──────────┐ │
  │  │ Critical│ │  High   │ │  Medium  │ │
  │  │    2    │ │   15    │ │    42    │ │
  │  └─────────┘ └─────────┘ └──────────┘ │
  │                                         │
  │  Standards Compliance:                  │
  │  CIS Benchmark:    78% passed          │
  │  AWS Best Practices: 92% passed        │
  │                                         │
  │  Top Failed Controls:                   │
  │  1. IAM.4 — Root has access key        │
  │  2. S3.1  — Bucket without encryption  │
  │  3. EC2.8 — IMDSv2 not required        │
  └─────────────────────────────────────────┘
```

### Cải thiện Security Score:

```
Quick wins (dễ fix):
  1. Enable MFA cho root account        → +5 points
  2. Block S3 public access             → +3 points
  3. Enable encryption at rest (RDS/S3) → +3 points
  4. Require IMDSv2 for EC2             → +2 points
  5. Rotate IAM access keys > 90 days   → +2 points
```

---

## 🔗 Tài liệu tham khảo

- [Security Hub User Guide](https://docs.aws.amazon.com/securityhub/latest/userguide/what-is-securityhub.html) ⭐⭐⭐
- [CIS AWS Benchmark](https://www.cisecurity.org/benchmark/amazon_web_services) ⭐⭐
- [ASFF Format](https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-findings-format.html) ⭐
