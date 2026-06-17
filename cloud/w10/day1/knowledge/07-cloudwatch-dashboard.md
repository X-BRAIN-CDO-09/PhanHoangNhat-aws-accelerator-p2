# CloudWatch Dashboard — Visualize Production Health

> **Nguồn:** W10-D1 | **Chủ đề:** CloudWatch Dashboard

---

## 1. Dashboard là gì?

**CloudWatch Dashboard** là trang web tuỳ chỉnh trong CloudWatch Console để visualize metrics, alarms, và logs — tương tự **Grafana Dashboard** (W9).

### Đặc điểm:

- **Cross-account / Cross-region** — xem metrics từ nhiều account/region trên 1 dashboard
- **Auto-refresh** — tự cập nhật (10s, 1m, 5m)
- **Widget types** — Metric, Text, Alarm, Log, Explorer
- **Free** — 3 dashboards đầu tiên miễn phí, $3/month/dashboard sau đó

---

## 2. Widget Types

| Widget | Mô tả | Use case |
|---|---|---|
| **Line** | Time series chart | CPU, latency theo thời gian |
| **Stacked area** | Area chart xếp chồng | Requests by endpoint |
| **Number** | Single value | Current CPU, Active users |
| **Gauge** | Đồng hồ đo | Disk usage (0-100%) |
| **Bar** | Bar chart | Error count by service |
| **Pie** | Pie chart | Traffic distribution |
| **Alarm** | Hiển thị alarm status | Production alarms overview |
| **Text** | Markdown text | Documentation, notes |
| **Log** | Embedded log query | Recent errors |
| **Explorer** | Dynamic metric explorer | Auto-discover metrics |

---

## 3. Tạo Dashboard bằng Terraform

```hcl
# Tạo Dashboard bằng Terraform
resource "aws_cloudwatch_dashboard" "production" {
  dashboard_name = "Production-Overview"
  
  dashboard_body = jsonencode({
    widgets = [
      # Row 1: Service Health
      {
        type   = "metric"
        x = 0; y = 0; width = 8; height = 6
        properties = {
          title  = "ALB Request Count & 5xx Rate"
          view   = "timeSeries"
          metrics = [
            ["AWS/ApplicationELB", "RequestCount",              
             "LoadBalancer", aws_lb.main.arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", 
             "LoadBalancer", aws_lb.main.arn_suffix],
          ]
          period = 300
          stat   = "Sum"
        }
      },
      # Row 1: CPU Overview
      {
        type   = "metric"
        x = 8; y = 0; width = 8; height = 6
        properties = {
          title  = "EC2 CPU Utilization"
          view   = "timeSeries"
          metrics = [
            ["AWS/EC2", "CPUUtilization", 
             "AutoScalingGroupName", aws_autoscaling_group.app.name,
             { stat = "Average" }]
          ]
          period = 300
          yAxis = { left = { min = 0, max = 100 } }
        }
      },
      # Alarm status widget
      {
        type   = "alarm"
        x = 16; y = 0; width = 8; height = 6
        properties = {
          title  = "Production Alarms"
          alarms = [
            aws_cloudwatch_metric_alarm.high_cpu.arn,
            aws_cloudwatch_metric_alarm.alb_5xx.arn,
          ]
        }
      },
    ]
  })
}
```

---

## 4. Dashboard Layout

Dashboard dùng **grid system** 24 columns × unlimited rows:

```
x=0       x=8       x=16      x=24
├─────────┼─────────┼─────────┤
│ ALB     │ EC2 CPU │ Alarms  │  y=0, height=6
│ Traffic │         │ Status  │
│         │         │         │
├─────────┼─────────┼─────────┤  y=6
│ Memory  │ Disk    │ Logs    │
│ Usage   │ Usage   │ Errors  │
│         │         │         │
├─────────┴─────────┴─────────┤  y=12
```

### Positioning:

| Property | Mô tả |
|---|---|
| `x` | Column position (0-23) |
| `y` | Row position (0+) |
| `width` | Width in columns (1-24) |
| `height` | Height in rows (1+) |

---

## 5. Best Practices cho Production Dashboard

```
Layout recommendations:
  Row 1: HIGH-LEVEL HEALTH
    → Alarm status, overall request rate, error rate
    
  Row 2: COMPUTE RESOURCES  
    → CPU, Memory, Disk (per-service hoặc per-ASG)
    
  Row 3: APPLICATION METRICS
    → Latency (p50, p99), throughput, queue depth
    
  Row 4: BUSINESS METRICS
    → Orders/min, revenue, active users
    
  Row 5: LOGS
    → Recent errors, slow queries
```

### Golden Signals (Google SRE):

| Signal | CloudWatch Metric | Dashboard Widget |
|---|---|---|
| **Latency** | ALB TargetResponseTime | Line chart (p50, p95, p99) |
| **Traffic** | ALB RequestCount | Line chart |
| **Errors** | ALB HTTPCode_5XX | Line chart + Number |
| **Saturation** | EC2 CPU + Memory | Line chart + Gauge |

---

## 6. Share Dashboard

```
Sharing options:
  1. Share within AWS Account (IAM permissions)
  2. Share cross-account (CloudWatch cross-account)
  3. Public share (anyone with link — cẩn thận!)
  4. Embed trong iframe (internal tools)
```

---

## 🔗 Tài liệu tham khảo

- [CloudWatch Dashboard Guide](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch_Dashboards.html) ⭐⭐
- [Dashboard Widget Types](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/create-and-work-with-widgets.html) ⭐
