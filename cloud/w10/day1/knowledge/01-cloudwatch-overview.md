# CloudWatch — Tổng quan kiến trúc

> **Nguồn:** W10-D1 | **Chủ đề:** AWS CloudWatch: Monitoring, Alarms & SNS

---

## CloudWatch là gì?

**CloudWatch = AWS native observability platform** tích hợp sâu với tất cả AWS services.

CloudWatch cung cấp khả năng:
- **Monitoring** — theo dõi metrics của mọi AWS service
- **Logging** — thu thập, lưu trữ và query log
- **Alerting** — cảnh báo khi metric vi phạm ngưỡng
- **Dashboard** — visualize production health

---

## Kiến trúc tổng quan

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

### Các thành phần chính

| Thành phần | Mô tả | Ví dụ |
|---|---|---|
| **Metrics** | Dữ liệu số theo thời gian | CPU, Memory, RequestCount |
| **Logs** | Text log từ services | Application logs, VPC Flow Logs |
| **Alarms** | Cảnh báo khi metric vượt ngưỡng | CPU > 80% → gửi email |
| **Dashboards** | Giao diện trực quan | Production overview |
| **Events/EventBridge** | Phản ứng với thay đổi state | EC2 terminated → notify |
| **Container Insights** | Monitoring cho ECS/EKS | Pod CPU, Node memory |

---

## So sánh CloudWatch vs Prometheus/Grafana (W9)

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

### Khi nào dùng cái nào?

```
CloudWatch:
  ✅ Dùng khi workload 100% trên AWS
  ✅ Muốn zero-config, tích hợp sẵn
  ✅ Cần cross-service correlation
  ⚠️ Chi phí tăng theo volume

Prometheus + Grafana:
  ✅ Hybrid/multi-cloud
  ✅ Kubernetes-native
  ✅ Cần PromQL (mạnh hơn)
  ⚠️ Phải tự vận hành
```

> **Thực tế production:** Nhiều team dùng **cả hai** — CloudWatch cho AWS infrastructure metrics, Prometheus/Grafana cho application-level metrics trong Kubernetes.

---

## 🔗 Tài liệu tham khảo

- [CloudWatch User Guide](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring) ⭐⭐⭐
- [AWS Observability Best Practices](https://aws-observability.github.io/observability-best-practices) ⭐
