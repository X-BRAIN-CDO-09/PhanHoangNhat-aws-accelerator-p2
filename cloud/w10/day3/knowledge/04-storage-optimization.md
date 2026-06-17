# Storage Optimization — S3 Lifecycle, EBS, Cost Saving

> **Nguồn:** W10-D3 | **Chủ đề:** Storage Cost Optimization

---

## 1. S3 Storage Classes

AWS S3 có nhiều storage classes với **chi phí** và **access pattern** khác nhau:

```
         Truy cập thường xuyên
              ↑
    ┌─────────────────────┐
    │   S3 Standard       │  $0.023/GB/month
    │   (Frequent Access) │  Truy cập mọi lúc
    └─────────┬───────────┘
              │ Ít truy cập hơn
    ┌─────────┴───────────┐
    │   S3 Standard-IA    │  $0.0125/GB/month
    │   (Infrequent)      │  Min 30 ngày, phí retrieval
    └─────────┬───────────┘
              │ Hiếm khi truy cập
    ┌─────────┴───────────┐
    │   S3 Glacier IR     │  $0.004/GB/month
    │   (Instant Retrieval│  Min 90 ngày
    └─────────┬───────────┘
              │ Archive
    ┌─────────┴───────────┐
    │  S3 Glacier Flexible│  $0.0036/GB/month
    │  (Archive)          │  Retrieval: phút → giờ
    └─────────┬───────────┘
              │ Long-term archive
    ┌─────────┴───────────┐
    │  S3 Glacier Deep    │  $0.00099/GB/month
    │  Archive            │  Retrieval: 12-48 giờ
    └─────────────────────┘
              ↓
         Truy cập hiếm khi
```

### So sánh chi tiết:

| Storage Class | Giá/GB/month | Min Duration | Retrieval | Use case |
|---|---|---|---|---|
| **Standard** | $0.023 | Không | Instant | Hot data, frequent access |
| **Standard-IA** | $0.0125 | 30 ngày | Instant, phí/GB | Backup, DR |
| **One Zone-IA** | $0.01 | 30 ngày | Instant, phí/GB | Reproducible data |
| **Glacier IR** | $0.004 | 90 ngày | Instant | Archive cần access nhanh |
| **Glacier Flexible** | $0.0036 | 90 ngày | 1-12 giờ | Long-term archive |
| **Glacier Deep** | $0.00099 | 180 ngày | 12-48 giờ | Compliance, 7+ năm |
| **Intelligent-Tiering** | $0.023 + monitoring | Không | Auto-tiered | Unpredictable access |

### S3 Intelligent-Tiering:

```
S3 Intelligent-Tiering tự động di chuyển data:
  
  Truy cập thường xuyên → Frequent Access tier
  Sau 30 ngày không truy cập → Infrequent Access tier
  Sau 90 ngày → Archive Instant Access tier
  Sau 90+ ngày (optional) → Archive Access tier
  Sau 180+ ngày (optional) → Deep Archive Access tier
  
  Chi phí: $0.0025/1000 objects/month (monitoring fee)
  → Phù hợp cho data có access pattern không rõ ràng
```

---

## 2. S3 Lifecycle Rules

### Terraform — Lifecycle Policy

```hcl
# s3-lifecycle.tf

resource "aws_s3_bucket" "data" {
  bucket = "my-app-data-${var.environment}"
}

resource "aws_s3_bucket_lifecycle_configuration" "data" {
  bucket = aws_s3_bucket.data.id
  
  # Rule 1: Logs → IA sau 30 ngày → Glacier sau 90 ngày → Xoá sau 365 ngày
  rule {
    id     = "logs-lifecycle"
    status = "Enabled"
    
    filter {
      prefix = "logs/"
    }
    
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
    
    expiration {
      days = 365  # Xoá sau 1 năm
    }
  }
  
  # Rule 2: Backup → Glacier Deep Archive sau 7 ngày
  rule {
    id     = "backup-lifecycle"
    status = "Enabled"
    
    filter {
      prefix = "backups/"
    }
    
    transition {
      days          = 7
      storage_class = "DEEP_ARCHIVE"
    }
    
    expiration {
      days = 2555  # Xoá sau 7 năm
    }
  }
  
  # Rule 3: Xoá incomplete multipart uploads sau 7 ngày
  rule {
    id     = "cleanup-multipart"
    status = "Enabled"
    
    filter {
      prefix = ""  # Tất cả objects
    }
    
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
  
  # Rule 4: Xoá old versions sau 30 ngày (nếu versioning enabled)
  rule {
    id     = "cleanup-old-versions"
    status = "Enabled"
    
    filter {
      prefix = ""
    }
    
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }
    
    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}
```

### Lifecycle Timeline:

```
Ngày 0:     Upload file → S3 Standard ($0.023/GB)
Ngày 30:    Lifecycle → S3 Standard-IA ($0.0125/GB)
Ngày 90:    Lifecycle → S3 Glacier ($0.0036/GB)
Ngày 365:   Lifecycle → DELETE

Savings: 
  365 ngày Standard: 365 × $0.023/30 = $0.28/GB
  Lifecycle:         30×$0.023/30 + 60×$0.0125/30 + 275×$0.0036/30 = $0.081/GB
  → Tiết kiệm 71%! 🎉
```

---

## 3. EBS Volume Optimization

### gp2 → gp3 Migration

```
gp2 (General Purpose SSD - old):
  - IOPS scale with volume size (3 IOPS/GB)
  - Max 16,000 IOPS
  - $0.10/GB/month

gp3 (General Purpose SSD - new):
  - 3,000 IOPS baseline (regardless of size)
  - Max 16,000 IOPS (independently provisioned)
  - $0.08/GB/month
  → 20% rẻ hơn, hiệu suất tốt hơn!
```

### Terraform:

```hcl
# Dùng gp3 thay vì gp2
resource "aws_ebs_volume" "data" {
  availability_zone = "ap-southeast-1a"
  size              = 100
  type              = "gp3"      # ← gp3, không phải gp2
  iops              = 3000       # Baseline IOPS
  throughput        = 125        # Baseline throughput (MB/s)
  encrypted         = true
  
  tags = {
    Name = "app-data-volume"
  }
}
```

### Tìm và migrate gp2 volumes:

```bash
# Tìm tất cả gp2 volumes
aws ec2 describe-volumes \
  --filters "Name=volume-type,Values=gp2" \
  --query 'Volumes[].{ID:VolumeId,Size:Size,State:State}'

# Migrate gp2 → gp3
aws ec2 modify-volume \
  --volume-id vol-0123456789 \
  --volume-type gp3 \
  --iops 3000 \
  --throughput 125
```

---

## 4. CloudWatch Logs Retention

CloudWatch Logs **mặc định giữ vĩnh viễn** — tốn chi phí rất nhiều!

```hcl
# Set retention cho log groups
resource "aws_cloudwatch_log_group" "app" {
  name              = "/myapp/production"
  retention_in_days = 30          # Chỉ giữ 30 ngày

  # Retention options:
  # 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 
  # 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3653
}
```

### Export old logs to S3 (rẻ hơn):

```bash
# Export log group to S3
aws logs create-export-task \
  --log-group-name "/myapp/production" \
  --from 1609459200000 \
  --to 1612137600000 \
  --destination "my-log-archive-bucket" \
  --destination-prefix "cloudwatch-exports"
```

---

## 5. Cost Savings Summary

| Action | Effort | Savings | Timeline |
|---|---|---|---|
| Delete unused EBS volumes | ⭐ Low | $10-100/month | Ngay lập tức |
| gp2 → gp3 migration | ⭐ Low | 20% EBS cost | 1 ngày |
| S3 Lifecycle rules | ⭐⭐ Medium | 50-70% S3 cost | 1 tuần |
| CloudWatch Logs retention | ⭐ Low | 30-90% logs cost | Ngay lập tức |
| Release unused Elastic IPs | ⭐ Low | $3.6/IP/month | Ngay lập tức |
| Stop dev/staging nights | ⭐⭐ Medium | 65% dev cost | 1 tuần |
| Savings Plans | ⭐⭐ Medium | 40-60% compute | Cần analysis |
| Spot instances | ⭐⭐⭐ High | 70-90% batch cost | 2-4 tuần |

---

## 🔗 Tài liệu tham khảo

- [S3 Storage Classes](https://aws.amazon.com/s3/storage-classes) ⭐⭐⭐
- [S3 Lifecycle Configuration](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html) ⭐⭐⭐
- [EBS Volume Types](https://docs.aws.amazon.com/ebs/latest/userguide/ebs-volume-types.html) ⭐⭐
- [CloudWatch Logs Pricing](https://aws.amazon.com/cloudwatch/pricing/) ⭐
