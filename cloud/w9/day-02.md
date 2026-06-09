# W9 — D2: Observability — SLO/SLI/OTel

> **Ngày:** T3 09/06/2026 | **Theme:** Deliver Smartly
> **Commit prefix:** `[W9-D2]`
> **🎙️ Liên quan: Live với mentor Minh T4 15h–17h (Monitoring/Observability)**

---

## 🎯 Mục tiêu học tập

Sau ngày hôm nay, bạn có thể:

- [ ] Phân biệt SLI, SLO, SLA và giải thích Error Budget
- [ ] Mô tả 3 pillars of Observability (Metrics, Logs, Traces)
- [ ] Hiểu OpenTelemetry SDK + Collector hoạt động như thế nào
- [ ] Cấu hình Prometheus scrape + Grafana dashboard cơ bản
- [ ] Thiết kế multi-window burn rate alert (fast + slow)
- [ ] Tích hợp Loki để thu thập log

---

## 📚 Kiến thức trọng tâm

### 1. SLI / SLO / SLA / Error Budget — Nền tảng tư duy

#### Định nghĩa

| Khái niệm | Định nghĩa | Ví dụ |
|---|---|---|
| **SLI** (Service Level Indicator) | Metric cụ thể đo lường chất lượng service | `% request thành công trong 30 ngày` |
| **SLO** (Service Level Objective) | Ngưỡng mục tiêu cho SLI | `Availability ≥ 99.9%` |
| **SLA** (Service Level Agreement) | Cam kết pháp lý với khách hàng, có penalty | `SLA 99.5% — vi phạm → hoàn tiền` |
| **Error Budget** | Lượng lỗi được phép có trong kỳ | `0.1% của 30 ngày = 43.8 phút downtime` |

#### Error Budget — Công cụ ra quyết định

```
Error Budget = 1 - SLO target
Ví dụ SLO 99.9% → Error Budget = 0.1%

Trong 30 ngày (43,200 phút):
  0.1% × 43,200 = 43.2 phút được phép lỗi
```

**Dùng Error Budget để quyết định:**
- Budget còn nhiều → deploy nhanh, thử nghiệm feature mới ✅
- Budget gần cạn → freeze deploy, tập trung reliability 🚨
- Budget đã hết → incident response, không deploy thêm ❌

---

### 2. The 3 Pillars of Observability

```
┌─────────────────────────────────────────────────────────────┐
│                    OBSERVABILITY                            │
│                                                             │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐             │
│  │ METRICS  │    │  LOGS    │    │  TRACES  │             │
│  │          │    │          │    │          │             │
│  │ "What is │    │ "What    │    │ "Where   │             │
│  │ happening│    │ happened │    │ did time │             │
│  │ now?"    │    │ exactly?"│    │ go?"     │             │
│  │          │    │          │    │          │             │
│  │Prometheus│    │  Loki    │    │  Jaeger  │             │
│  │ Grafana  │    │  Grafana │    │  Tempo   │             │
│  └──────────┘    └──────────┘    └──────────┘             │
└─────────────────────────────────────────────────────────────┘
```

| Pillar | Công dụng | Tool |
|---|---|---|
| **Metrics** | Số liệu tổng hợp theo thời gian, alert, dashboard | Prometheus + Grafana |
| **Logs** | Chi tiết sự kiện, debug lỗi cụ thể | Loki + Grafana |
| **Traces** | Theo dõi request qua nhiều service (distributed tracing) | Jaeger / Tempo |

---

### 3. OpenTelemetry (OTel) — Chuẩn thống nhất

#### Tại sao OTel?

Trước OTel, mỗi vendor có SDK riêng (Datadog SDK, Jaeger SDK...). OTel chuẩn hóa cách thu thập telemetry data, vendor-neutral.

#### Kiến trúc OTel

```
┌─────────────────────────────────────────────────────────────────┐
│  Application                                                    │
│  ┌─────────────────────────────┐                               │
│  │  OTel SDK                   │                               │
│  │  - Traces (spans)           │──────────────┐                │
│  │  - Metrics (counters, hist) │              ▼                │
│  │  - Logs (structured)        │   ┌──────────────────────┐   │
│  └─────────────────────────────┘   │  OTel Collector      │   │
│                                    │                      │   │
│                                    │  Receivers:          │   │
│                                    │  - OTLP (gRPC/HTTP)  │   │
│                                    │  - Prometheus        │   │
│                                    │                      │   │
│                                    │  Processors:         │   │
│                                    │  - Batch             │   │
│                                    │  - Filter            │   │
│                                    │  - Transform         │   │
│                                    │                      │   │
│                                    │  Exporters:          │   │
│                                    │  - Prometheus        │──▶│ Prometheus
│                                    │  - Loki              │──▶│ Loki
│                                    │  - Jaeger/Tempo      │──▶│ Jaeger
│                                    └──────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

#### OTel Collector config cơ bản

```yaml
# otel/collector-config.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317   # app gửi trace/metric đến đây
      http:
        endpoint: 0.0.0.0:4318
  prometheus:
    config:
      scrape_configs:
        - job_name: 'otel-collector'
          static_configs:
            - targets: ['localhost:8888']

processors:
  batch:
    timeout: 5s
    send_batch_size: 1000
  memory_limiter:
    limit_mib: 400

exporters:
  prometheus:
    endpoint: "0.0.0.0:8889"   # Prometheus scrape từ đây
  loki:
    endpoint: http://loki:3100/loki/api/v1/push
  jaeger:
    endpoint: jaeger:14250
    tls:
      insecure: true

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [jaeger]
    metrics:
      receivers: [otlp, prometheus]
      processors: [batch, memory_limiter]
      exporters: [prometheus]
    logs:
      receivers: [otlp]
      processors: [batch]
      exporters: [loki]
```

---

### 4. Prometheus — Thu thập và lưu trữ Metrics

#### Kiến trúc Prometheus

```
Prometheus Server
  │
  ├── Scrape (pull model): GET /metrics từ targets
  ├── TSDB: lưu time-series data
  ├── PromQL: query language
  └── Alert Manager: gửi alert
```

#### Prometheus scrape config

```yaml
# prometheus/prometheus.yml
global:
  scrape_interval: 15s      # scrape mỗi 15 giây
  evaluation_interval: 15s  # evaluate rule mỗi 15 giây

scrape_configs:
  - job_name: 'my-app'
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
```

#### PromQL — Các query cơ bản cần biết

```promql
# Availability SLI: tỷ lệ request thành công
sum(rate(http_requests_total{status!~"5.."}[5m])) /
sum(rate(http_requests_total[5m]))

# Latency SLI: p99 latency
histogram_quantile(0.99, 
  sum(rate(http_request_duration_seconds_bucket[5m])) by (le)
)

# Error rate (%)
sum(rate(http_requests_total{status=~"5.."}[5m])) /
sum(rate(http_requests_total[5m])) * 100

# CPU usage by pod
sum(rate(container_cpu_usage_seconds_total[5m])) by (pod)
```

---

### 5. Grafana — Visualization

#### Cấu trúc Grafana Dashboard

```
Dashboard
  ├── Row 1: "SLO Overview"
  │   ├── Panel: Availability (gauge — % so với SLO target)
  │   ├── Panel: Error Budget remaining (stat)
  │   └── Panel: P99 Latency (time series)
  ├── Row 2: "Traffic"
  │   ├── Panel: Request rate (time series)
  │   └── Panel: Error rate (time series)
  └── Row 3: "Resources"
      ├── Panel: CPU usage (time series)
      └── Panel: Memory usage (time series)
```

#### Datasource configuration (Grafana)

```yaml
# grafana/datasources/datasources.yaml
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    url: http://prometheus:9090
    isDefault: true
  - name: Loki
    type: loki
    url: http://loki:3100
```

---

### 6. Loki — Log Aggregation

#### Kiến trúc Loki

```
App pods → Promtail (agent) → Loki → Grafana (LogQL)
```

**Promtail** là log shipping agent, tương tự Filebeat nhưng cho Loki.

#### Promtail config cơ bản

```yaml
# loki/promtail-config.yaml
server:
  http_listen_port: 9080

positions:
  filename: /tmp/positions.yaml

clients:
  - url: http://loki:3100/loki/api/v1/push

scrape_configs:
  - job_name: kubernetes-pods
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_name]
        target_label: pod
      - source_labels: [__meta_kubernetes_namespace]
        target_label: namespace
    pipeline_stages:
      - json:
          expressions:
            level: level
            message: message
      - labels:
          level:
```

#### LogQL — Query cơ bản

```logql
# Lọc log error của pod
{namespace="my-app", pod=~"my-app-.*"} |= "ERROR"

# Đếm error rate theo thời gian
sum(rate({namespace="my-app"} |= "ERROR" [5m])) by (pod)

# Filter JSON log
{namespace="my-app"} | json | level = "error"
```

---

### 7. Multi-Window Burn Rate Alert ⭐ (Quan trọng nhất)

#### Tại sao cần multi-window?

Single-window alert có vấn đề:
- **Quá nhạy (short window):** Nhiều false positive, alert khi chỉ có vài lỗi nhỏ
- **Quá chậm (long window):** Phát hiện lỗi quá trễ, budget đã hết

#### Khái niệm Burn Rate

```
Burn Rate = Tốc độ tiêu Error Budget

Ví dụ SLO 99.9% (Error Budget = 0.1%):
  - Burn Rate 1 = tiêu budget đúng tốc độ bình thường (hết sau 30 ngày)
  - Burn Rate 14.4 = hết budget sau 2 giờ  ← CRITICAL alert
  - Burn Rate 6 = hết budget sau 5 giờ     ← WARNING alert
  - Burn Rate 1 = hết budget sau 30 ngày   ← Bình thường
```

#### Google's Multi-Window Burn Rate Strategy

| Alert | Window ngắn | Window dài | Burn Rate | Thời gian hết budget |
|---|---|---|---|---|
| **Page (Critical)** | 5 phút | 1 giờ | 14.4x | ~2 giờ |
| **Page (High)** | 30 phút | 6 giờ | 6x | ~5 giờ |
| **Ticket (Medium)** | 2 giờ | 24 giờ | 3x | ~10 giờ |
| **Ticket (Low)** | 6 giờ | 3 ngày | 1x | ~30 ngày |

**Nguyên tắc:** Alert chỉ khi CÙNG LÚC cả 2 window đều vượt ngưỡng burn rate.

#### PromQL cho Multi-Window Burn Rate Alert

```yaml
# alerts/slo-burn-rate.yaml
groups:
  - name: slo-burn-rate
    rules:
      # SLI: tỷ lệ request thành công
      # ---------- CRITICAL: Burn rate 14.4x ----------
      - alert: SLOBurnRateCritical
        expr: |
          (
            # Fast window: 5 phút
            sum(rate(http_requests_total{status!~"5.."}[5m])) /
            sum(rate(http_requests_total[5m])) < (1 - 14.4 * 0.001)
          )
          and
          (
            # Slow window: 1 giờ
            sum(rate(http_requests_total{status!~"5.."}[1h])) /
            sum(rate(http_requests_total[1h])) < (1 - 14.4 * 0.001)
          )
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "SLO Critical — burn rate {{ $value | humanizePercentage }}"
          description: |
            Error budget đang cạn rất nhanh (burn rate 14.4x).
            Budget sẽ hết trong ~2 giờ nếu không xử lý.

      # ---------- HIGH: Burn rate 6x ----------
      - alert: SLOBurnRateHigh
        expr: |
          (
            # Fast window: 30 phút
            sum(rate(http_requests_total{status!~"5.."}[30m])) /
            sum(rate(http_requests_total[30m])) < (1 - 6 * 0.001)
          )
          and
          (
            # Slow window: 6 giờ
            sum(rate(http_requests_total{status!~"5.."}[6h])) /
            sum(rate(http_requests_total[6h])) < (1 - 6 * 0.001)
          )
        for: 15m
        labels:
          severity: warning
        annotations:
          summary: "SLO High — burn rate elevated"
          description: |
            Error budget đang cạn nhanh (burn rate 6x).
            Budget sẽ hết trong ~5 giờ nếu không xử lý.
```

---

### 8. SLO Dashboard Design

```
SLO Dashboard — "Availability 99.9%"
┌─────────────────────────────────────────────────────┐
│  [STAT] Current Availability    [STAT] Error Budget  │
│         98.5% ⚠️                        -72%         │
├─────────────────────────────────────────────────────┤
│  [TIME SERIES] Availability over 30 days            │
│  ─────────────────────────────── 99.9% target       │
│                     ~~~~~~~~~~~~~~                  │
├─────────────────────────────────────────────────────┤
│  [TIME SERIES] Burn Rate (1h + 6h windows)          │
│  ─────────────────────── 14.4x CRITICAL             │
│  ─────────────────────── 6x WARNING                 │
│  ~~~~~~~~~~~~~~~~~~~~                               │
├─────────────────────────────────────────────────────┤
│  [TABLE] Active Alerts          [HEATMAP] Error rate │
└─────────────────────────────────────────────────────┘
```

---

## 🔗 Tài liệu tham khảo (Ưu tiên đọc theo thứ tự)

| Tài liệu | Link | Ưu tiên |
|---|---|---|
| Google SRE Book — SLO chapter | https://sre.google/sre-book/service-level-objectives | ⭐⭐⭐ Đọc trước |
| Implementing SLOs (Workbook) | https://sre.google/workbook/implementing-slos | ⭐⭐⭐ Quan trọng |
| Multi-window Burn Rate Alert | https://sre.google/workbook/alerting-on-slos | ⭐⭐⭐ Cốt lõi |
| OpenTelemetry Concepts | https://opentelemetry.io/docs/concepts | ⭐⭐ Hiểu kiến trúc |
| Prometheus Getting Started | https://prometheus.io/docs/introduction/overview | ⭐⭐ Thực hành |
| Grafana Docs | https://grafana.com/docs/grafana/latest | ⭐⭐ Thực hành |
| Loki Getting Started | https://grafana.com/docs/loki/latest/get-started | ⭐ Tham khảo |

---

## 🏗️ Cấu trúc thư mục thực hành

```
cloud/w9/day-b/
├── otel/
│   ├── collector-config.yaml       # OTel Collector config
│   └── collector-deployment.yaml   # K8s Deployment
├── prometheus/
│   ├── prometheus.yml              # Scrape config
│   └── deployment.yaml
├── grafana/
│   ├── datasources/
│   │   └── datasources.yaml
│   └── dashboards/
│       └── slo-dashboard.json      # Dashboard as code
├── loki/
│   ├── loki-config.yaml
│   └── promtail-config.yaml
└── alert-rules/
    ├── slo-burn-rate.yaml          # Multi-window burn rate alert
    └── latency-slo.yaml
```

---

## ✅ Checklist tự kiểm tra

- [ ] Giải thích được SLI vs SLO vs SLA + Error Budget
- [ ] Tính Error Budget cho SLO 99.9% trong 30 ngày
- [ ] Phân biệt 3 pillars: Metrics / Logs / Traces
- [ ] Vẽ kiến trúc OTel: SDK → Collector → Backend
- [ ] Viết PromQL query tính Availability SLI
- [ ] Hiểu tại sao cần multi-window (không dùng single window)
- [ ] Giải thích Burn Rate 14.4x nghĩa là gì
- [ ] Viết được alert rule cho Fast (5m/1h) + Slow (30m/6h) window
- [ ] Phân biệt Loki vs Prometheus (logs vs metrics)

---

## 📝 Chuẩn bị cho Live Session T4 (15h–17h với mentor Minh)

**Câu hỏi nên chuẩn bị hỏi:**

1. Trong thực tế, SLO target chọn 99.9% hay 99.5% — dựa vào tiêu chí nào?
2. Khi error budget hết, quy trình freeze deploy trong team thực tế như thế nào?
3. OTel Collector nên deploy kiểu gì trong K8s — DaemonSet hay Deployment?
4. Thực tế có nên instrument code ở application layer hay dùng auto-instrumentation?

**Ghi chú trong live:**

<!-- Ghi lại trong buổi live -->

---

## 📝 Ghi chú cá nhân

**Câu hỏi / Vướng mắc:**

**Điểm đã hiểu rõ:**

**Kế hoạch thực hành:**
