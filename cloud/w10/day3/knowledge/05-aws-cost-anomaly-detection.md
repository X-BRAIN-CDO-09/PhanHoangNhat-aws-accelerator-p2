# 05 — AWS Cost Anomaly Detection

> **Scope:** Cost Anomaly Detection, Budget alerts, Cost Allocation Tags, Terraform

---

## 1. AWS Cost Anomaly Detection là gì?

**Cost Anomaly Detection** = AWS ML-based service tự động phát hiện **chi phí bất thường** — spike do misconfiguration, runaway resources, hoặc attack.

```
Normal daily cost: ~$50/day
        │
        ▼
┌────────────────────────────────────────┐
│  Cost Anomaly Detection                 │
│                                          │
│  Day 1: $50  ✅ Normal                  │
│  Day 2: $48  ✅ Normal                  │
│  Day 3: $52  ✅ Normal                  │
│  Day 4: $250 ❌ ANOMALY! (+400%)       │
│         │                                │
│         ▼                                │
│  SNS Alert → Slack → On-call            │
│  "Cost spike detected: EC2 in us-east-1 │
│   $200 increase. Root cause: 50 new      │
│   m5.xlarge instances."                  │
└────────────────────────────────────────┘
```

### Tại sao cần?

| Scenario | Impact |
|---|---|
| Developer tạo 100 EC2 instances, quên terminate | $$$$ bill shock |
| HPA scale đến max replicas, stuck | $$$ cost runaway |
| NAT Gateway bandwidth spike (data exfil?) | $$ + security risk |
| Forgot to delete test RDS cluster | $$$ monthly waste |
| Crypto mining (compromised instance) | $$$$ + security breach |

---

## 2. Setup Cost Anomaly Detection

### AWS Console

```
Cost Management → Cost Anomaly Detection → Create monitor

Monitor type:
├── AWS Service — monitor theo từng service (EC2, RDS, S3...)
├── Linked Account — monitor theo AWS account
├── Cost Category — monitor theo custom cost category
└── Cost Allocation Tag — monitor theo tag (team, project)
```

### Terraform

```hcl
# cost-anomaly.tf

# Monitor: theo AWS Service (recommended)
resource "aws_ce_anomaly_monitor" "service_monitor" {
  name              = "service-anomaly-monitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"               # Monitor mỗi service
  
  tags = {
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# Monitor: theo Cost Allocation Tag
resource "aws_ce_anomaly_monitor" "tag_monitor" {
  name         = "team-cost-monitor"
  monitor_type = "CUSTOM"
  
  monitor_specification = jsonencode({
    And = null
    Or  = null
    Not = null
    Dimensions = {
      Key          = "LINKED_ACCOUNT"
      Values       = [data.aws_caller_identity.current.account_id]
      MatchOptions = ["EQUALS"]
    }
    Tags = {
      Key          = "Team"
      Values       = ["platform", "backend", "frontend"]
      MatchOptions = ["EQUALS"]
    }
  })
}

# Subscription: SNS alert
resource "aws_ce_anomaly_subscription" "alert" {
  name = "cost-anomaly-alerts"
  
  monitor_arn_list = [
    aws_ce_anomaly_monitor.service_monitor.arn,
    aws_ce_anomaly_monitor.tag_monitor.arn,
  ]
  
  frequency = "DAILY"                          # DAILY | IMMEDIATE | WEEKLY
  
  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      values        = ["50"]                   # Alert nếu impact > $50
      match_options = ["GREATER_THAN_OR_EQUAL"]
    }
  }
  
  subscriber {
    type    = "SNS"
    address = aws_sns_topic.cost_alerts.arn
  }
  
  # Hoặc Email
  subscriber {
    type    = "EMAIL"
    address = "platform-team@company.com"
  }
}

# SNS Topic cho cost alerts
resource "aws_sns_topic" "cost_alerts" {
  name = "cost-anomaly-alerts"
}

resource "aws_sns_topic_subscription" "slack" {
  topic_arn = aws_sns_topic.cost_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.slack_cost_alert.arn
}
```

---

## 3. AWS Budgets

AWS Budgets = set **hard budget** + alert khi đạt threshold.

```hcl
# budget-alerts.tf

# Monthly budget
resource "aws_budgets_budget" "monthly" {
  name         = "monthly-total-budget"
  budget_type  = "COST"
  limit_amount = "5000"                       # $5000/month
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  
  # Alert 1: 80% threshold
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["platform-team@company.com"]
    subscriber_sns_topic_arns  = [aws_sns_topic.cost_alerts.arn]
  }
  
  # Alert 2: 100% threshold
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["manager@company.com"]
    subscriber_sns_topic_arns  = [aws_sns_topic.cost_alerts.arn]
  }
  
  # Alert 3: Forecasted to exceed
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = ["platform-team@company.com"]
  }
  
  # Filter by tag
  cost_filter {
    name   = "TagKeyValue"
    values = ["user:Environment$production"]   # Chỉ production
  }
}

# Per-service budget (EKS specific)
resource "aws_budgets_budget" "eks" {
  name         = "eks-monthly-budget"
  budget_type  = "COST"
  limit_amount = "2000"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  
  cost_filter {
    name   = "Service"
    values = ["Amazon Elastic Kubernetes Service"]
  }
  
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_sns_topic_arns  = [aws_sns_topic.cost_alerts.arn]
  }
}
```

---

## 4. Cost Allocation Tags

Tags cho phép break down cost theo team/project/environment.

```hcl
# Activate cost allocation tags (phải activate trong Billing console)
# Console: Billing → Cost allocation tags → Activate

# Standard tags for cost tracking
locals {
  common_tags = {
    Environment = var.environment
    Team        = var.team
    Project     = var.project
    ManagedBy   = "terraform"
    CostCenter  = var.cost_center
  }
}

# Apply to ALL resources
resource "aws_instance" "app" {
  # ...
  tags = merge(local.common_tags, {
    Name = "app-server"
  })
}

resource "aws_eks_cluster" "main" {
  # ...
  tags = local.common_tags
}
```

### Tag Policy (AWS Organizations)

```json
{
  "tags": {
    "Team": {
      "tag_key": {
        "@@assign": "Team"
      },
      "tag_value": {
        "@@assign": [
          "platform",
          "backend",
          "frontend",
          "data",
          "devops"
        ]
      },
      "enforced_for": {
        "@@assign": [
          "ec2:instance",
          "ec2:volume",
          "rds:db",
          "eks:cluster",
          "s3:bucket"
        ]
      }
    },
    "Environment": {
      "tag_key": {
        "@@assign": "Environment"
      },
      "tag_value": {
        "@@assign": [
          "production",
          "staging",
          "development"
        ]
      }
    }
  }
}
```

---

## 5. Cost Explorer Queries

```bash
# CLI: Get cost by service (last 30 days)
aws ce get-cost-and-usage \
  --time-period Start=$(date -d "30 days ago" +%Y-%m-%d),End=$(date +%Y-%m-%d) \
  --granularity DAILY \
  --metrics "BlendedCost" \
  --group-by Type=DIMENSION,Key=SERVICE \
  --query 'ResultsByTime[*].Groups[*].[Keys[0],Metrics.BlendedCost.Amount]' \
  --output table

# Cost by tag
aws ce get-cost-and-usage \
  --time-period Start=2024-01-01,End=2024-01-31 \
  --granularity MONTHLY \
  --metrics "BlendedCost" \
  --group-by Type=TAG,Key=Team \
  --output table

# Cost forecast (next 30 days)
aws ce get-cost-forecast \
  --time-period Start=$(date +%Y-%m-%d),End=$(date -d "30 days" +%Y-%m-%d) \
  --metric BLENDED_COST \
  --granularity MONTHLY
```

---

## 6. K8s Cost Optimization

### Kubecost (optional — K8s cost visibility)

```bash
# Install Kubecost
helm install kubecost kubecost/cost-analyzer \
  --namespace kubecost \
  --create-namespace

# Access dashboard
kubectl port-forward -n kubecost svc/kubecost-cost-analyzer 9090:9090
# http://localhost:9090
```

### K8s-level cost guardrails

```
1. ResourceQuota → prevent resource explosion
2. LimitRange → default limits for every container
3. HPA maxReplicas → cap on scaling
4. Spot instances for non-critical workloads
5. Karpenter/CA → right-size nodes
6. Cost allocation by namespace (Kubecost)
```

---

## 7. Cost Alert Architecture

```
┌─────────────┐     ┌──────────────┐     ┌───────────┐
│ AWS Cost     │────►│ Cost Anomaly │────►│ SNS Topic │
│ Data         │     │ Detection    │     │           │
│              │     │ (ML-based)   │     └─────┬─────┘
└─────────────┘     └──────────────┘           │
                                                ├──► Email
┌─────────────┐     ┌──────────────┐           ├──► Lambda → Slack
│ AWS Budget  │────►│ Threshold    │───────────┤
│ $5000/month │     │ 80%, 100%    │           └──► PagerDuty (P1)
└─────────────┘     └──────────────┘

Combined strategy:
├── Anomaly Detection: "Something unusual happened" (reactive)
├── Budget alerts: "Approaching limit" (proactive)  
└── Kubecost: "Which namespace/team costs most?" (visibility)
```

---

## 8. Best Practices

| Practice | Giải thích |
|---|---|
| **Tag everything** | Không tag = không track = waste |
| **Budget per team** | Mỗi team biết budget, chịu trách nhiệm |
| **Anomaly detection DAILY** | Catch issues nhanh |
| **Review weekly** | Cost review meeting |
| **Right-size monthly** | AWS Compute Optimizer recommendations |
| **Spot for non-prod** | 60-90% savings cho staging/dev |
| **Reserved/Savings Plans** | Commit 1-3 year cho stable workloads |
| **Auto-shutdown dev** | Tắt dev resources ngoài giờ làm |
