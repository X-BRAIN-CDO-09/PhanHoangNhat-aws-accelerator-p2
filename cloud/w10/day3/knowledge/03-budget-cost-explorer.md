# AWS Budgets & Cost Explorer

> **Nguồn:** W10-D3 | **Chủ đề:** Cost Management

---

## 1. AWS Budgets — Thiết lập alert

**AWS Budgets** cho phép set spending limits và nhận alert khi chi phí vượt ngưỡng.

### Budget Types:

| Loại | Mô tả | Use case |
|---|---|---|
| **Cost Budget** | Giới hạn chi phí ($) | "Không chi quá $500/month" |
| **Usage Budget** | Giới hạn usage | "Không quá 1000 EC2 hours" |
| **Savings Plans Budget** | Track Savings Plans utilization | "SP utilization > 80%" |
| **Reservation Budget** | Track RI utilization | "RI utilization > 90%" |

---

## 2. Tạo Budget bằng Terraform

```hcl
# budget.tf

# Budget tổng cho toàn account
resource "aws_budgets_budget" "monthly_total" {
  name         = "monthly-total-${var.environment}"
  budget_type  = "COST"
  limit_amount = "500"            # $500/month
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  
  # Period
  time_period_start = "2026-06-01_00:00"
  
  # Alert khi đạt 80%
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["team@company.com"]
  }
  
  # Alert khi đạt 100%
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["team@company.com", "manager@company.com"]
  }
  
  # Alert khi forecast vượt 100%
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = ["team@company.com"]
  }
}

# Budget theo service (ví dụ: chỉ cho EC2)
resource "aws_budgets_budget" "ec2_budget" {
  name         = "ec2-budget-${var.environment}"
  budget_type  = "COST"
  limit_amount = "200"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  
  time_period_start = "2026-06-01_00:00"
  
  # Filter theo service
  cost_filter {
    name   = "Service"
    values = ["Amazon Elastic Compute Cloud - Compute"]
  }
  
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["team@company.com"]
  }
}
```

### Tạo bằng CLI:

```bash
aws budgets create-budget \
  --account-id 123456789 \
  --budget '{
    "BudgetName": "Monthly-Total",
    "BudgetLimit": {"Amount": "500", "Unit": "USD"},
    "TimeUnit": "MONTHLY",
    "BudgetType": "COST"
  }' \
  --notifications-with-subscribers '[
    {
      "Notification": {
        "NotificationType": "ACTUAL",
        "ComparisonOperator": "GREATER_THAN",
        "Threshold": 80,
        "ThresholdType": "PERCENTAGE"
      },
      "Subscribers": [
        {"SubscriptionType": "EMAIL", "Address": "team@company.com"}
      ]
    }
  ]'
```

---

## 3. Cost Explorer — Phân tích chi phí

**Cost Explorer** giúp visualize, understand, và manage AWS costs.

### Các view hữu ích:

```
1. Monthly costs by service
   → Xem service nào tốn nhất
   
2. Daily costs trend
   → Phát hiện spike bất thường
   
3. Costs by tag (Environment, Team)
   → Phân bổ chi phí theo team/project
   
4. Reserved Instance utilization
   → RI có đang được dùng hiệu quả?
   
5. Savings Plans utilization
   → SP coverage đủ chưa?
```

### Cost Explorer API:

```bash
# Lấy chi phí tháng này theo service
aws ce get-cost-and-usage \
  --time-period Start=2026-06-01,End=2026-06-30 \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --group-by Type=DIMENSION,Key=SERVICE
```

---

## 4. Cost Allocation Tags

**Tags** cho phép phân bổ chi phí theo team, project, environment:

### Setup:

```
Bước 1: Tag resources
  Environment: production | staging | dev
  Team:        platform | backend | data
  Project:     order-service | user-service
  CostCenter:  CC-1001 | CC-1002

Bước 2: Activate tags trong Billing Console
  AWS Console → Billing → Cost allocation tags → Activate

Bước 3: Xem trong Cost Explorer
  Group by: Tag → Team → Xem chi phí mỗi team
```

### Terraform — Enforce tags:

```hcl
# Thêm default tags cho tất cả resources
provider "aws" {
  region = var.region
  
  default_tags {
    tags = {
      Environment = var.environment
      Team        = var.team
      Project     = var.project
      ManagedBy   = "terraform"
    }
  }
}
```

---

## 5. AWS Cost Anomaly Detection

**Cost Anomaly Detection** dùng ML để phát hiện chi phí bất thường:

```hcl
resource "aws_ce_anomaly_monitor" "service" {
  name              = "service-anomaly-monitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_subscription" "alert" {
  name      = "cost-anomaly-alert"
  frequency = "DAILY"
  
  monitor_arn_list = [
    aws_ce_anomaly_monitor.service.arn
  ]
  
  subscriber {
    type    = "EMAIL"
    address = "team@company.com"
  }
  
  # Chỉ alert khi anomaly > $50
  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      values        = ["50"]
      match_options = ["GREATER_THAN_OR_EQUAL"]
    }
  }
}
```

---

## 6. Cost Optimization Quick Wins

```
1. DELETE UNUSED RESOURCES (miễn phí!)
   □ Unattached EBS volumes
   □ Unused Elastic IPs
   □ Old snapshots (> 30 days)
   □ Idle load balancers
   □ Unused NAT Gateways ($32/month!)

2. RIGHTSIZE (Compute Optimizer)
   □ Check AWS Compute Optimizer recommendations
   □ Downsize over-provisioned instances
   □ Switch to newer generation (m4 → m5 → m6i)

3. SCHEDULING
   □ Stop dev/staging instances nights & weekends
   □ Use AWS Instance Scheduler
   □ Savings: 65% cho dev environments

4. STORAGE
   □ S3 Lifecycle (→ IA → Glacier)
   □ EBS gp2 → gp3 (20% rẻ hơn, hiệu suất tốt hơn)
   □ Delete old CloudWatch Logs
```

### Script tìm unused resources:

```bash
# Tìm unattached EBS volumes
aws ec2 describe-volumes \
  --filters "Name=status,Values=available" \
  --query 'Volumes[].{ID:VolumeId,Size:Size,Created:CreateTime}'

# Tìm unused Elastic IPs
aws ec2 describe-addresses \
  --query 'Addresses[?AssociationId==null].{IP:PublicIp,AllocationId:AllocationId}'

# Tìm idle Load Balancers (0 healthy targets)
aws elbv2 describe-target-health \
  --target-group-arn <arn> \
  --query 'TargetHealthDescriptions[?TargetHealth.State!=`healthy`]'
```

---

## 🔗 Tài liệu tham khảo

- [AWS Budgets Guide](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html) ⭐⭐⭐
- [Cost Explorer Guide](https://docs.aws.amazon.com/cost-management/latest/userguide/ce-what-is.html) ⭐⭐
- [Cost Anomaly Detection](https://docs.aws.amazon.com/cost-management/latest/userguide/manage-ad.html) ⭐⭐
