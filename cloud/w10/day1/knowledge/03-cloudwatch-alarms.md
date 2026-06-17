# CloudWatch Alarms — Tạo và cấu hình

> **Nguồn:** W10-D1 | **Chủ đề:** CloudWatch Alarms

---

## 1. Anatomy of a CloudWatch Alarm

Mỗi CloudWatch Alarm bao gồm các thành phần:

```
CloudWatch Alarm
├── Metric / Math Expression      ← Metric nào cần monitor
├── Period (60s, 300s, 3600s...)  ← Độ dài mỗi data point
├── Evaluation Periods (N)        ← Số period để evaluate
├── Datapoints to Alarm (M)       ← Số datapoints phải vi phạm trong N periods
├── Threshold                     ← Ngưỡng (ví dụ: 80)
├── Comparison Operator           ← >=, >, <, <=
├── Treat Missing Data            ← missing | ignore | notBreaching | breaching
└── Actions:
    ├── In Alarm  → SNS topic / Auto Scaling / EC2 action
    ├── OK        → SNS topic
    └── Insufficient Data → SNS topic
```

### Hiểu rõ Period, Evaluation Periods, Datapoints to Alarm

```
Ví dụ: period=300, evaluation_periods=3, datapoints_to_alarm=2

Timeline:  |--5min--|--5min--|--5min--|
Data:      |  85%   |  75%   |  90%   |
Threshold: ----80%-----80%-----80%----
Vi phạm:   |   ✅   |   ❌   |   ✅   |

→ 2 trong 3 data points vi phạm → Alarm TRIGGERED! ✅
```

### Treat Missing Data

| Giá trị | Hành vi | Khi nào dùng |
|---|---|---|
| `missing` | Giữ nguyên state hiện tại | Default — an toàn nhất |
| `ignore` | Bỏ qua, không tính | Metric không liên tục |
| `notBreaching` | Coi như OK | Metric chỉ xuất hiện khi có vấn đề |
| `breaching` | Coi như vi phạm | Metric phải luôn có (nếu mất = lỗi) |

---

## 2. Tạo Alarm bằng AWS CLI

```bash
# Tạo alarm CPU cao
aws cloudwatch put-metric-alarm \
  --alarm-name "EC2-High-CPU-Production" \
  --alarm-description "Alert khi CPU > 80% trong 5 phút" \
  --metric-name CPUUtilization \
  --namespace AWS/EC2 \
  --statistic Average \
  --dimensions "Name=InstanceId,Value=i-0123456789abcdef0" \
  --period 300 \
  --evaluation-periods 2 \
  --datapoints-to-alarm 2 \
  --threshold 80 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --treat-missing-data missing \
  --alarm-actions "arn:aws:sns:ap-southeast-1:123456789:alerts-topic" \
  --ok-actions    "arn:aws:sns:ap-southeast-1:123456789:alerts-topic"
```

---

## 3. Tạo Alarm bằng Terraform

### Alarm đơn giản — CPU

```hcl
# cloudwatch.tf

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "EC2-High-CPU-${var.environment}"
  alarm_description   = "Alert khi CPU > 80% trong 10 phút"
  
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  statistic           = "Average"
  
  dimensions = {
    InstanceId = aws_instance.app.id
  }
  
  period              = 300             # 5 phút mỗi data point
  evaluation_periods  = 2              # Evaluate 2 data points (= 10 phút)
  datapoints_to_alarm = 2              # Cả 2 phải vi phạm
  threshold           = 80
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "missing"
  
  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
  
  tags = {
    Environment = var.environment
    Team        = "platform"
  }
}
```

### Alarm với Metric Math — Error Rate

```hcl
# Alarm cho ALB 5xx errors
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "ALB-High-5XX-Rate"
  alarm_description   = "Error rate > 5% trong 5 phút"
  
  # Dùng Metric Math
  metric_query {
    id          = "error_rate"
    expression  = "errors / requests * 100"
    label       = "Error Rate (%)"
    return_data = true
  }
  
  metric_query {
    id = "errors"
    metric {
      metric_name = "HTTPCode_Target_5XX_Count"
      namespace   = "AWS/ApplicationELB"
      period      = 300
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.main.arn_suffix
      }
    }
  }
  
  metric_query {
    id = "requests"
    metric {
      metric_name = "RequestCount"
      namespace   = "AWS/ApplicationELB"
      period      = 300
      stat        = "Sum"
      dimensions = {
        LoadBalancer = aws_lb.main.arn_suffix
      }
    }
  }
  
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  
  alarm_actions = [aws_sns_topic.alerts.arn]
}
```

---

## 4. Composite Alarm — Kết hợp nhiều alarm

**Composite Alarm** cho phép kết hợp nhiều alarm bằng logic AND/OR/NOT:

```hcl
# Chỉ alert khi CẢ HAI điều kiện đều xảy ra
resource "aws_cloudwatch_composite_alarm" "critical_production" {
  alarm_name = "Critical-Production-Incident"
  
  alarm_rule = "ALARM(${aws_cloudwatch_metric_alarm.high_cpu.alarm_name}) AND ALARM(${aws_cloudwatch_metric_alarm.alb_5xx.alarm_name})"
  
  alarm_actions = [aws_sns_topic.pagerduty.arn]
}
```

### Tại sao dùng Composite Alarm?

```
Không dùng Composite:
  CPU > 80%     → Page on-call  ← Có thể false positive
  5xx rate > 5% → Page on-call  ← Có thể false positive
  = 2 alerts riêng lẻ → Alert storm! 😰

Dùng Composite:
  CPU > 80% AND 5xx > 5% → Page on-call
  = 1 alert chính xác → Chỉ page khi thực sự có incident 🎯
```

> **Best Practice:** Dùng Composite Alarm cho production alerting để tránh **alert storm** — chỉ page on-call khi nhiều signal cùng xấu.

---

## 5. Alarm States

```
                ┌─────────────────┐
                │  INSUFFICIENT   │  ← Không đủ data
                │     DATA        │
                └────────┬────────┘
                         │
              ┌──────────┴──────────┐
              ▼                     ▼
    ┌──────────────┐      ┌──────────────┐
    │      OK      │◄────►│    ALARM     │
    │              │      │              │
    └──────────────┘      └──────────────┘
```

| State | Mô tả | Action thường thấy |
|---|---|---|
| **OK** | Metric trong ngưỡng bình thường | Gửi recovery notification |
| **ALARM** | Metric vi phạm ngưỡng | SNS → Email/Slack/PagerDuty |
| **INSUFFICIENT_DATA** | Không đủ data để evaluate | Kiểm tra metric source |

---

## 🔗 Tài liệu tham khảo

- [CloudWatch Alarms Best Practices](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html) ⭐⭐⭐
- [Composite Alarms](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Create_Composite_Alarm.html) ⭐⭐
