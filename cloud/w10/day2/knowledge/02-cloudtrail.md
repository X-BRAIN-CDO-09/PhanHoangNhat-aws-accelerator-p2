# CloudTrail — Audit Trail & Compliance

> **Nguồn:** W10-D2 | **Chủ đề:** AWS CloudTrail

---

## 1. CloudTrail là gì?

**CloudTrail** ghi lại **MỌI API call** đến AWS account — ai đã làm gì, khi nào, từ đâu.

```
Mọi action trên AWS → API Call → CloudTrail Event

Ví dụ:
  Ai:     user/admin (arn:aws:iam::123456789:user/admin)
  Làm gì: s3:DeleteBucket
  Lúc nào: 2026-06-17T10:30:00Z
  Từ đâu:  IP 203.0.113.50
  Kết quả: Success
```

### Use cases:

- **Security audit**: Ai đã access production resources?
- **Compliance**: Chứng minh ai đã thay đổi gì, khi nào
- **Troubleshooting**: Ai đã xoá resource gây lỗi?
- **Incident response**: Truy vết hành vi đáng ngờ

---

## 2. Event Types

| Loại | Mô tả | Ví dụ | Chi phí |
|---|---|---|---|
| **Management Events** | Control plane operations | `CreateBucket`, `RunInstances`, `DeleteUser` | Free (90 ngày) |
| **Data Events** | Data plane operations | `GetObject`, `PutObject`, `Invoke` | Phí thêm |
| **Insights Events** | Phát hiện bất thường | Spike trong API calls | Phí thêm |

### Management vs Data Events:

```
Management Events (mặc định bật):
  ✅ CreateBucket, DeleteBucket
  ✅ RunInstances, TerminateInstances
  ✅ CreateUser, AttachPolicy
  ✅ CreateSecurityGroup, AuthorizeSecurityGroupIngress
  → "Ai đã tạo/xoá/thay đổi cấu hình?"

Data Events (phải bật riêng):
  📊 s3:GetObject, s3:PutObject
  📊 lambda:Invoke
  📊 dynamodb:GetItem, dynamodb:PutItem
  → "Ai đã đọc/ghi dữ liệu?"
  ⚠️ Volume rất lớn → chi phí cao
```

---

## 3. Cấu trúc CloudTrail Event

```json
{
  "eventVersion": "1.08",
  "userIdentity": {
    "type": "IAMUser",
    "principalId": "AIDAEXAMPLE",
    "arn": "arn:aws:iam::123456789:user/admin",
    "accountId": "123456789",
    "userName": "admin"
  },
  "eventTime": "2026-06-17T10:30:00Z",
  "eventSource": "s3.amazonaws.com",
  "eventName": "DeleteBucket",
  "awsRegion": "ap-southeast-1",
  "sourceIPAddress": "203.0.113.50",
  "userAgent": "aws-cli/2.15.0",
  "requestParameters": {
    "bucketName": "important-data-bucket"
  },
  "responseElements": null,
  "errorCode": null,
  "errorMessage": null
}
```

### Các fields quan trọng:

| Field | Mô tả | Dùng để |
|---|---|---|
| `userIdentity` | Ai thực hiện | Xác định người/service |
| `eventTime` | Khi nào | Timeline sự kiện |
| `eventName` | Action gì | Phân loại hành vi |
| `sourceIPAddress` | IP nguồn | Phát hiện IP lạ |
| `errorCode` | Lỗi (nếu có) | Phát hiện unauthorized attempts |

---

## 4. Tạo Trail bằng Terraform

```hcl
# S3 bucket để lưu CloudTrail logs
resource "aws_s3_bucket" "cloudtrail" {
  bucket = "my-cloudtrail-logs-${data.aws_caller_identity.current.account_id}"
  
  tags = {
    Purpose = "CloudTrail"
  }
}

# Bucket policy cho CloudTrail
resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# CloudTrail
resource "aws_cloudtrail" "main" {
  name                       = "main-trail"
  s3_bucket_name             = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true   # IAM, STS events (global)
  is_multi_region_trail      = true      # Tất cả regions
  enable_log_file_validation = true      # Detect log tampering
  
  # Gửi logs vào CloudWatch Logs (để query nhanh)
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cw.arn
  
  # Event selectors
  event_selector {
    read_write_type           = "All"
    include_management_events = true
    
    # Data events cho S3 (optional, phí thêm)
    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::important-bucket/"]
    }
  }
  
  tags = {
    Environment = var.environment
  }
}

# CloudWatch Log Group cho CloudTrail
resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/main"
  retention_in_days = 90
}
```

---

## 5. Query CloudTrail — Ai đã xoá S3 bucket?

### Cách 1: CloudWatch Logs Insights

```sql
-- Tìm ai đã xoá S3 bucket
fields eventTime, userIdentity.userName, eventName, 
       requestParameters.bucketName, sourceIPAddress
| filter eventName = "DeleteBucket"
| sort eventTime desc
| limit 20
```

### Cách 2: AWS CLI

```bash
# Tìm events trong 24h qua
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=DeleteBucket \
  --start-time "2026-06-16T00:00:00Z" \
  --end-time "2026-06-17T23:59:59Z" \
  --region ap-southeast-1
```

### Cách 3: Athena (cho lượng lớn data)

```sql
-- Tạo bảng Athena từ CloudTrail logs
CREATE EXTERNAL TABLE cloudtrail_logs (
  eventVersion STRING,
  userIdentity STRUCT<
    type: STRING,
    principalId: STRING,
    arn: STRING,
    accountId: STRING,
    userName: STRING
  >,
  eventTime STRING,
  eventSource STRING,
  eventName STRING,
  awsRegion STRING,
  sourceIPAddress STRING,
  userAgent STRING,
  errorCode STRING,
  errorMessage STRING,
  requestParameters STRING,
  responseElements STRING
)
ROW FORMAT SERDE 'org.apache.hive.hcatalog.data.JsonSerDe'
LOCATION 's3://my-cloudtrail-logs/AWSLogs/123456789/CloudTrail/';

-- Query: Ai đã xoá resources quan trọng?
SELECT 
  eventTime,
  userIdentity.userName,
  eventName,
  sourceIPAddress,
  errorCode
FROM cloudtrail_logs
WHERE eventName LIKE 'Delete%'
  AND eventTime > '2026-06-01'
ORDER BY eventTime DESC
LIMIT 100;
```

---

## 6. CloudTrail Best Practices

```
✅ Enable multi-region trail (không chỉ 1 region)
✅ Enable log file validation (phát hiện tampering)
✅ Gửi logs vào CloudWatch Logs (query real-time)
✅ Bật S3 versioning cho trail bucket (không mất data)
✅ Encrypt logs bằng KMS
✅ Restrict access to trail bucket (chỉ security team)
✅ Set up CloudWatch Alarm cho critical events:
   - Root account usage
   - IAM policy changes
   - Security group changes
   - Console login without MFA
```

---

## 🔗 Tài liệu tham khảo

- [CloudTrail User Guide](https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-user-guide.html) ⭐⭐⭐
- [CloudTrail + Athena](https://docs.aws.amazon.com/athena/latest/ug/cloudtrail-logs.html) ⭐⭐
