# CloudWatch Agent — Custom Metrics từ EC2

> **Nguồn:** W10-D1 | **Chủ đề:** CloudWatch Agent

---

## 1. CloudWatch Agent là gì?

**CloudWatch Agent** là daemon chạy trên EC2 để thu thập:
- **System metrics**: Memory, Disk usage (không có sẵn trong EC2 default metrics)
- **Custom metrics**: Từ file / stdin / StatsD / collectd
- **Logs**: Đẩy file log lên CloudWatch Logs

### Tại sao cần CloudWatch Agent?

```
EC2 Default Metrics (tự động):
  ✅ CPUUtilization
  ✅ NetworkIn/Out
  ✅ DiskReadOps/WriteOps
  ✅ StatusCheckFailed
  ❌ Memory          ← KHÔNG CÓ!
  ❌ Disk Usage (%)  ← KHÔNG CÓ!
  ❌ TCP Connections ← KHÔNG CÓ!

CloudWatch Agent bổ sung:
  ✅ mem_used_percent
  ✅ disk_used_percent
  ✅ netstat_tcp_established
  ✅ Application logs → CloudWatch Logs
```

---

## 2. Cài đặt CloudWatch Agent

### Amazon Linux 2023

```bash
sudo dnf install -y amazon-cloudwatch-agent
```

### Ubuntu / Debian

```bash
wget https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
sudo dpkg -i -E ./amazon-cloudwatch-agent.deb
```

### Prerequisite: IAM Role cho EC2

EC2 cần IAM Role với policy `CloudWatchAgentServerPolicy` để gửi metrics/logs:

```hcl
# Terraform
resource "aws_iam_role_policy_attachment" "cw_agent" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}
```

---

## 3. CloudWatch Agent Config

File config JSON định nghĩa những gì agent thu thập:

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

### Giải thích các section:

| Section | Mô tả |
|---|---|
| `agent` | Cấu hình chung: interval, user |
| `metrics.namespace` | Custom namespace (thay vì `CWAgent` default) |
| `metrics.append_dimensions` | Tự động thêm dimension cho mọi metric |
| `metrics.metrics_collected.cpu` | Thu thập CPU chi tiết (per-core hoặc total) |
| `metrics.metrics_collected.mem` | Thu thập Memory |
| `metrics.metrics_collected.disk` | Thu thập Disk usage |
| `metrics.metrics_collected.netstat` | Thu thập network connections |
| `logs.logs_collected.files` | Đẩy file log lên CloudWatch Logs |

---

## 4. Khởi động và kiểm tra Agent

```bash
# Khởi động agent với config
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s

# Kiểm tra status
sudo systemctl status amazon-cloudwatch-agent

# Xem log của agent (debug)
sudo tail -f /opt/aws/amazon-cloudwatch-agent/logs/amazon-cloudwatch-agent.log
```

### Các lệnh quản lý:

| Lệnh | Mô tả |
|---|---|
| `-a fetch-config` | Load config và start |
| `-a start` | Start agent |
| `-a stop` | Stop agent |
| `-a status` | Kiểm tra status |
| `-m ec2` | Mode EC2 (vs on-premises) |

---

## 5. Dùng SSM Parameter Store cho config (best practice)

Thay vì lưu config trên local EC2, lưu trên **SSM Parameter Store**:

```bash
# Upload config lên SSM
aws ssm put-parameter \
  --name "/cloudwatch-agent/config" \
  --type String \
  --value file://cloudwatch-agent-config.json

# Fetch config từ SSM
sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c ssm:/cloudwatch-agent/config \
  -s
```

> **Best Practice:** Dùng SSM Parameter Store để quản lý config tập trung — dễ update cho nhiều EC2 cùng lúc.

---

## 🔗 Tài liệu tham khảo

- [CloudWatch Agent Config Reference](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Agent-Configuration-File-Details.html) ⭐⭐
- [Install CloudWatch Agent](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/install-CloudWatch-Agent-on-EC2-Instance.html) ⭐⭐
