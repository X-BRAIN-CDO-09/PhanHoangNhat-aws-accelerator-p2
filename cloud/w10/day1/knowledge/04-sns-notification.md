# SNS — Simple Notification Service

> **Nguồn:** W10-D1 | **Chủ đề:** SNS Notification & Integration

---

## 1. SNS là gì?

**SNS (Simple Notification Service)** là managed pub/sub messaging service của AWS, dùng để gửi thông báo từ CloudWatch Alarms đến các endpoints.

---

## 2. Kiến trúc SNS Fan-Out

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

### Các protocol hỗ trợ:

| Protocol | Mô tả | Use case |
|---|---|---|
| `email` | Gửi email plain text | Dev/staging alerts |
| `email-json` | Email dạng JSON | Automation |
| `lambda` | Gọi Lambda function | Slack, Teams, custom logic |
| `sqs` | Đẩy vào SQS queue | Async processing |
| `https` | HTTP POST đến endpoint | PagerDuty, Opsgenie |
| `sms` | Gửi SMS | Chỉ một số regions |

---

## 3. Tạo SNS Topic + Subscription bằng CLI

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

> **Lưu ý:** Email subscription cần **confirm** qua link trong email trước khi nhận notification.

---

## 4. Terraform: SNS Topic + Email

```hcl
# sns.tf

resource "aws_sns_topic" "alerts" {
  name = "production-alerts-${var.environment}"
  
  tags = {
    Environment = var.environment
  }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = "team@company.com"
}
```

---

## 5. Slack Integration qua Lambda

### Terraform: SNS + Lambda

```hcl
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

### Lambda Handler — Format Slack Message

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

### Flow hoàn chỉnh:

```
CloudWatch Alarm (CPU > 80%)
    ↓ trigger
SNS Topic "production-alerts"
    ↓ invoke
Lambda "slack-alert-notifier"
    ↓ HTTP POST
Slack Webhook → #alerts-production channel
    ↓ display
🔴 EC2-High-CPU-Production
   State: ALARM | Region: ap-southeast-1
   Reason: Threshold crossed...
```

---

## 6. SNS Message Filtering (nâng cao)

SNS hỗ trợ **filter policy** để subscriber chỉ nhận message phù hợp:

```json
{
  "severity": ["CRITICAL", "HIGH"],
  "environment": ["production"]
}
```

> Giúp tránh team nhận quá nhiều alert không liên quan.

---

## 🔗 Tài liệu tham khảo

- [SNS Developer Guide](https://docs.aws.amazon.com/sns/latest/dg/welcome.html) ⭐⭐
- [SNS Message Filtering](https://docs.aws.amazon.com/sns/latest/dg/sns-message-filtering.html) ⭐
