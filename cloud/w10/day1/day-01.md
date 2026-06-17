# W10 — D1: AWS CloudWatch — Monitoring & Alerting

> **Ngày:** T2 16/06/2026 | **Theme:** Operate Confidently on AWS
> **Commit prefix:** `[W10-D1]`

---

## 🎯 Mục tiêu học tập

Sau ngày hôm nay, bạn có thể:

- [ ] Giải thích kiến trúc CloudWatch và sự khác biệt với Prometheus/Grafana (W9)
- [ ] Phân biệt CloudWatch Metrics, Logs, Alarms, Dashboards, và Insights
- [ ] Tạo CloudWatch Alarm với đúng threshold, period, và evaluation
- [ ] Cấu hình SNS Topic để gửi alert đến Email / Slack / PagerDuty
- [ ] Viết CloudWatch Agent config để thu thập custom metrics từ EC2
- [ ] Dùng CloudWatch Logs Insights để query và debug log

---

## 📚 Kiến thức trọng tâm

### 1. CloudWatch — Tổng quan kiến trúc

**CloudWatch = AWS native observability platform** tích hợp sâu với tất cả AWS services.

```
┌─────────────────────────────────────────────────────────────┐
│                      AWS CloudWatch                         │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐ │
│  │   METRICS    │  │    LOGS      │  │    ALARMS        │ │
│  │              │  │              │  │                  │ │
│  │ • AWS native │  │ • Log Groups │  │ • Threshold      │ │
│  │ • Custom     │  │ • Log Streams│  │ • Anomaly Detect │ │
│  │ • Math expr  │  │ • Insights   │  │ • Composite      │ │
│  └──────────────┘  └──────────────┘  └──────────────────┘ │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐ │
│  │  DASHBOARDS  │  │   EVENTS     │  │  CONTAINER       │ │
│  │              │  │  (EventBridge│  │  INSIGHTS        │ │
│  │ • Widgets    │  │   formerly)  │  │                  │ │
│  │ • Cross-acct │  │              │  │ • ECS / EKS      │ │
│  └──────────────┘  └──────────────┘  └──────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

#### So sánh CloudWatch vs Prometheus/Grafana (W9)

| Tiêu chí | CloudWatch | Prometheus + Grafana |
|---|---|---|
| **Tích hợp** | Native AWS, zero config | Cần cài đặt, cấu hình |
| **Chi phí** | Pay-per-use (có thể đắt) | Free (open source) |
| **Retention** | 15 tháng (metrics), tuỳ config (logs) | Tuỳ cấu hình storage |
| **Alerting** | CloudWatch Alarms + SNS | AlertManager |
| **Query** | CloudWatch Metrics Insights / Logs Insights | PromQL / LogQL |
| **Custom metric** | CloudWatch Agent / SDK | Prometheus exposition format |
| **Multi-cloud** | AWS only | Bất kỳ |
| **Phù hợp** | Pure AWS workloads | Hybrid, Kubernetes |

---

### 2. CloudWatch Metrics — Thu thập và lưu trữ

#### Namespace và Dimension

```
CloudWatch Metric = Namespace + MetricName + Dimensions + Timestamp + Value + Unit

Ví dụ:
  Namespace:  AWS/EC2
  MetricName: CPUUtilization
  Dimensions: {InstanceId: i-0123456789abcdef0}
  Value:      75.5
  Unit:       Percent
```

#### AWS-native metrics (không cần cấu hình)

| Service | Key Metrics |
|---|---|
| **EC2** | `CPUUtilization`, `NetworkIn/Out`, `DiskReadOps`, `StatusCheckFailed` |
| **RDS** | `DatabaseConnections`, `FreeStorageSpace`, `ReadLatency`, `WriteLatency` |
| **ELB/ALB** | `RequestCount`, `TargetResponseTime`, `HTTPCode_Target_5XX_Count` |
| **Lambda** | `Invocations`, `Errors`, `Duration`, `Throttles`, `ConcurrentExecutions` |
| **ECS** | `CPUUtilization`, `MemoryUtilization`, `RunningTaskCount` |
| **S3** | `BucketSizeBytes`, `NumberOfObjects`, `AllRequests` (cần enable) |

#### Custom Metrics — Gửi từ application

```python
# Dùng AWS SDK (boto3) để gửi custom metric
import boto3

cloudwatch = boto3.client('cloudwatch', region_name='ap-southeast-1')

# Gửi metric đơn
cloudwatch.put_metric_data(
    Namespace='MyApp/Production',
    MetricData=[
        {
            'MetricName': 'OrdersProcessed',
            'Dimensions': [
                {'Name': 'Environment', 'Value': 'production'},
                {'Name': 'Service',     'Value': 'order-service'},
            ],
            'Value': 42,
            'Unit': 'Count'
        },
        {
            'MetricName': 'OrderProcessingTime',
            'Dimensions': [
                {'Name': 'Environment', 'Value': 'production'},
            ],
            'Value': 1.25,
            'Unit': 'Seconds'
        }
    ]
)
```

#### Metric Math — Tính toán metric phức tạp

```
# Tính Error Rate từ 2 metrics
METRICS("AWS/ApplicationELB", "HTTPCode_Target_5XX_Count") /
METRICS("AWS/ApplicationELB", "RequestCount") * 100

# Tính tổng CPU từ nhiều instance
SUM(SEARCH('{AWS/EC2,InstanceId} MetricName="CPUUtilization"', 'Average', 300))
```

> **Metric Resolution:**
> - **Standard**: 1 phút (miễn phí)
> - **High Resolution**: 1-10 giây (phí thêm)

---

### 3. CloudWatch Alarms — Tạo và cấu hình

#### Anatomy of a CloudWatch Alarm

```
CloudWatch Alarm
├── Metric / Math Expression
├── Period (độ dài mỗi data point): 60s, 300s, 3600s...
├── Evaluation Periods (số period để evaluate): N periods
├── Datapoints to Alarm (số datapoints phải vi phạm trong N periods)
├── Threshold (ngưỡng)
├── Comparison Operator: >=, >, <, <=
├── Treat Missing Data: missing | ignore | notBreaching | breaching
└── Actions:
    ├── In Alarm → SNS topic / Auto Scaling / EC2 action
    ├── OK → SNS topic
    └── Insufficient Data → SNS topic
```

#### Ví dụ tạo Alarm bằng AWS CLI

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

#### Ví dụ tạo Alarm bằng Terraform

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

#### Composite Alarm — Kết hợp nhiều alarm

```hcl
# Chỉ alert khi CẢ HAI điều kiện đều xảy ra
resource "aws_cloudwatch_composite_alarm" "critical_production" {
  alarm_name = "Critical-Production-Incident"
  
  alarm_rule = "ALARM(${aws_cloudwatch_metric_alarm.high_cpu.alarm_name}) AND ALARM(${aws_cloudwatch_metric_alarm.alb_5xx.alarm_name})"
  
  alarm_actions = [aws_sns_topic.pagerduty.arn]
}
```

> **Tại sao dùng Composite Alarm?**
> Tránh alert storm — chỉ page on-call khi nhiều signal cùng xấu, không phải mỗi metric riêng lẻ.

---

### 4. SNS — Simple Notification Service

#### Kiến trúc SNS Fan-Out

```
CloudWatch Alarm
      │
      ▼
  SNS Topic ──────┬──► Email Subscription
                  ├──► Lambda (Slack webhook)
                  ├──► SQS Queue (async processing)
                  ├──► HTTPS Endpoint (PagerDuty / Opsgenie)
                  └──► SMS (chỉ US)
```

#### Tạo SNS Topic + Subscription

```bash
# Tạo SNS Topic
aws sns create-topic \
  --name production-alerts \
  --region ap-southeast-1

# Subscribe Email
aws sns subscribe \
  --topic-arn "arn:aws:sns:ap-southeast-1:123456789:production-alerts" \
  --protocol email \
  --notification-endpoint "team@company.com"

# Subscribe HTTPS (PagerDuty integration endpoint)
aws sns subscribe \
  --topic-arn "arn:aws:sns:ap-southeast-1:123456789:production-alerts" \
  --protocol https \
  --notification-endpoint "https://events.pagerduty.com/integration/..."
```

#### Terraform: SNS + Slack Integration qua Lambda

```hcl
# sns.tf

resource "aws_sns_topic" "alerts" {
  name = "production-alerts-${var.environment}"
  
  tags = {
    Environment = var.environment
  }
}

# Lambda để format và gửi Slack notification
resource "aws_lambda_function" "slack_notifier" {
  function_name = "slack-alert-notifier"
  role          = aws_iam_role.lambda_sns.arn
  handler       = "index.handler"
  runtime       = "python3.12"
  filename      = "lambda/slack_notifier.zip"
  
  environment {
    variables = {
      SLACK_WEBHOOK_URL = var.slack_webhook_url
      SLACK_CHANNEL     = "#alerts-production"
    }
  }
}

# Subscribe Lambda vào SNS
resource "aws_sns_topic_subscription" "lambda" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.slack_notifier.arn
}

# Cho phép SNS gọi Lambda
resource "aws_lambda_permission" "sns_invoke" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.slack_notifier.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alerts.arn
}
```

#### Lambda Handler — Format Slack Message

```python
# lambda/index.py
import json
import urllib.request
import os

def handler(event, context):
    sns_message = json.loads(event['Records'][0]['Sns']['Message'])
    
    alarm_name   = sns_message.get('AlarmName', 'Unknown Alarm')
    alarm_state  = sns_message.get('NewStateValue', 'UNKNOWN')
    alarm_reason = sns_message.get('NewStateReason', '')
    region       = sns_message.get('Region', '')
    
    # Chọn màu theo state
    color_map = {
        'ALARM':              '#FF0000',   # Đỏ
        'OK':                 '#00FF00',   # Xanh lá
        'INSUFFICIENT_DATA':  '#FFA500',   # Cam
    }
    color = color_map.get(alarm_state, '#808080')
    
    emoji_map = {
        'ALARM': '🔴',
        'OK':    '✅',
        'INSUFFICIENT_DATA': '⚠️',
    }
    emoji = emoji_map.get(alarm_state, '❓')
    
    slack_payload = {
        "channel":    os.environ['SLACK_CHANNEL'],
        "username":   "AWS CloudWatch",
        "icon_emoji": ":aws:",
        "attachments": [
            {
                "color": color,
                "title": f"{emoji} {alarm_name}",
                "fields": [
                    {"title": "State",  "value": alarm_state,  "short": True},
                    {"title": "Region", "value": region,        "short": True},
                    {"title": "Reason", "value": alarm_reason,  "short": False},
                ],
                "footer": "AWS CloudWatch",
                "ts":     sns_message.get('StateChangeTime', ''),
            }
        ]
    }
    
    webhook_url = os.environ['SLACK_WEBHOOK_URL']
    data        = json.dumps(slack_payload).encode('utf-8')
    req         = urllib.request.Request(webhook_url, data=data, 
                                         headers={'Content-Type': 'application/json'})
    urllib.request.urlopen(req)
    
    return {'statusCode': 200}
```

---

### 5. CloudWatch Agent — Custom Metrics từ EC2

**CloudWatch Agent** là daemon chạy trên EC2 để thu thập:
- **System metrics**: Memory, Disk usage (không có sẵn trong EC2 default metrics)
- **Custom metrics**: Từ file / stdin
- **Logs**: Đẩy file log lên CloudWatch Logs

#### Cài đặt CloudWatch Agent

```bash
# Amazon Linux 2023
sudo dnf install -y amazon-cloudwatch-agent

# Ubuntu / Debian
wget https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
sudo dpkg -i -E ./amazon-cloudwatch-agent.deb
```

#### CloudWatch Agent Config

```json
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "cwagent"
  },
  "metrics": {
    "namespace": "MyApp/EC2",
    "append_dimensions": {
      "InstanceId":   "${aws:InstanceId}",
      "InstanceType": "${aws:InstanceType}",
      "AutoScalingGroupName": "${aws:AutoScalingGroupName}"
    },
    "metrics_collected": {
      "cpu": {
        "resources":                ["*"],
        "measurement":              ["cpu_usage_idle", "cpu_usage_user", "cpu_usage_system"],
        "metrics_collection_interval": 60,
        "totalcpu":                 true
      },
      "mem": {
        "measurement": ["mem_used_percent", "mem_available_percent"]
      },
      "disk": {
        "resources":   ["/", "/data"],
        "measurement": ["used_percent", "inodes_free"],
        "ignore_file_system_types": ["sysfs", "devtmpfs"]
      },
      "netstat": {
        "measurement": ["tcp_established", "tcp_time_wait"]
      }
    }
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path":        "/var/log/app/application.log",
            "log_group_name":   "/myapp/production/application",
            "log_stream_name":  "{instance_id}",
            "timestamp_format": "%Y-%m-%dT%H:%M:%S",
            "retention_in_days": 30
          },
          {
            "file_path":       "/var/log/nginx/error.log",
            "log_group_name":  "/myapp/production/nginx-error",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
```

```bash
# Khởi động agent với config
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s

# Kiểm tra status
sudo systemctl status amazon-cloudwatch-agent
```

---

### 6. CloudWatch Logs Insights — Query và Debug

**Logs Insights** cho phép query log bằng SQL-like syntax.

#### Cú pháp cơ bản

```sql
-- Tìm tất cả ERROR logs trong 1 giờ qua
fields @timestamp, @message, @logStream
| filter @message like /ERROR/
| sort @timestamp desc
| limit 100

-- Đếm error theo loại
fields @message
| filter @message like /ERROR/
| parse @message "ERROR: * -" as error_type
| stats count(*) as error_count by error_type
| sort error_count desc

-- Tính p99 latency từ log có format JSON
fields @timestamp, response_time
| filter ispresent(response_time)
| stats pct(response_time, 99) as p99_latency,
        avg(response_time) as avg_latency,
        count(*) as request_count
  by bin(5m)

-- Top 10 slow requests
fields @timestamp, @message, response_time, path
| filter response_time > 1000
| sort response_time desc
| limit 10

-- Error rate theo endpoint
fields path, status_code
| filter status_code >= 500
| stats count(*) as errors by path
| sort errors desc
```

---

### 7. CloudWatch Dashboard — Visualize Production Health

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

## 🔗 Tài liệu tham khảo

| Tài liệu | Link | Ưu tiên |
|---|---|---|
| CloudWatch User Guide | https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring | ⭐⭐⭐ Đọc trước |
| CloudWatch Alarms Best Practices | https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/AlarmThatSendsEmail.html | ⭐⭐⭐ Quan trọng |
| CloudWatch Logs Insights Syntax | https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html | ⭐⭐⭐ Thực hành |
| SNS Developer Guide | https://docs.aws.amazon.com/sns/latest/dg/welcome.html | ⭐⭐ Cần biết |
| CloudWatch Agent Config Reference | https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Agent-Configuration-File-Details.html | ⭐⭐ Thực hành |
| AWS Observability Best Practices | https://aws-observability.github.io/observability-best-practices | ⭐ Nâng cao |

---

## 🏗️ Cấu trúc thư mục thực hành

```
cloud/w10/day1/
├── terraform/
│   ├── main.tf                    # Provider, locals
│   ├── cloudwatch-alarms.tf       # All CloudWatch Alarms
│   ├── sns.tf                     # SNS Topics + Subscriptions
│   ├── cloudwatch-dashboard.tf    # Dashboard
│   └── variables.tf
├── lambda/
│   └── slack_notifier/
│       ├── index.py               # Lambda handler
│       └── requirements.txt
└── cloudwatch-agent/
    └── config.json                # CloudWatch Agent config
```

---

## ✅ Checklist tự kiểm tra

- [ ] Giải thích sự khác biệt: CloudWatch vs Prometheus
- [ ] Liệt kê ít nhất 5 AWS-native metrics quan trọng cho EC2, ALB, Lambda
- [ ] Tạo CloudWatch Alarm cho CPU > 80% dùng Terraform
- [ ] Hiểu `period`, `evaluation_periods`, `datapoints_to_alarm` hoạt động thế nào
- [ ] Tạo SNS Topic và subscribe Email
- [ ] Viết Lambda để forward SNS → Slack
- [ ] Cài CloudWatch Agent và thu thập memory metric (không có trong EC2 default)
- [ ] Query CloudWatch Logs Insights: tìm ERROR, đếm theo loại, tính p99 latency
- [ ] Tạo CloudWatch Dashboard với ít nhất 3 widget
- [ ] Giải thích Composite Alarm và tại sao dùng nó

---

## 📝 Ghi chú cá nhân

<!-- Ghi lại những điểm khó hiểu, câu hỏi cần hỏi mentor -->

**Câu hỏi / Vướng mắc:**

**Điểm đã hiểu rõ:**

**Kế hoạch thực hành:**
