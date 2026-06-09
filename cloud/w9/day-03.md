# W9 — D3: Progressive Delivery — Canary với Argo Rollouts

> **Ngày:** T4 10/06/2026 | **Theme:** Deliver Smartly
> **Commit prefix:** `[W9-D3]`
> **🎙️ Hôm nay: Live Monitoring/Observability với mentor Minh 15h–17h**
> **📝 Online Test 1: 17h–18h (scope D1 + D2)**

---

## 🎯 Mục tiêu học tập

Sau ngày hôm nay, bạn có thể:

- [ ] Giải thích Progressive Delivery là gì và các chiến lược deploy
- [ ] Phân biệt Rollout CRD vs Deployment thông thường
- [ ] Cấu hình Canary deployment với Argo Rollouts
- [ ] Viết AnalysisTemplate dùng Prometheus query
- [ ] Định nghĩa abort criteria để auto-abort canary khi metric xấu
- [ ] Tích hợp burn rate alert từ D2 vào abort criteria

---

## 📚 Kiến thức trọng tâm

### 1. Progressive Delivery — Tổng quan

**Progressive Delivery = Kiểm soát rủi ro khi deploy bằng cách ra mắt dần dần, có metric-driven gate.**

#### Các chiến lược Progressive Delivery

```
┌─────────────────────────────────────────────────────────────────┐
│  RECREATE (Downtime)                                            │
│  v1 → [DOWN] → v2                                              │
│  ❌ Có downtime, không dùng cho production                      │
├─────────────────────────────────────────────────────────────────┤
│  ROLLING UPDATE (Default K8s)                                   │
│  v1 v1 v1 → v1 v1 v2 → v1 v2 v2 → v2 v2 v2                   │
│  ⚠️ Không kiểm soát được traffic, rollback chậm               │
├─────────────────────────────────────────────────────────────────┤
│  BLUE/GREEN                                                     │
│  [Blue=v1 100%] → [Green=v2 0%] → switch → [Green=v2 100%]    │
│  ✅ Zero downtime, rollback nhanh — nhưng tốn gấp đôi resource │
├─────────────────────────────────────────────────────────────────┤
│  CANARY ⭐ (Progressive Delivery)                               │
│  v1=100% → v1=90%/v2=10% → v1=70%/v2=30% → v2=100%           │
│  ✅ Kiểm soát rủi ro, metric-driven, auto-abort                │
└─────────────────────────────────────────────────────────────────┘
```

---

### 2. Argo Rollouts — Công cụ thực hiện

**Argo Rollouts** là K8s controller thêm vào CRD `Rollout` — thay thế `Deployment` khi cần Progressive Delivery.

#### Cài đặt Argo Rollouts

```bash
# Cài controller
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts \
  -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

# Cài kubectl plugin
kubectl argo rollouts version

# Hoặc cài plugin qua curl
curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
chmod +x kubectl-argo-rollouts-linux-amd64
sudo mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts
```

---

### 3. Rollout CRD — Cấu trúc và config

#### Rollout vs Deployment

```yaml
# Deployment (thông thường)
apiVersion: apps/v1
kind: Deployment         # ← thay bằng Rollout
metadata:
  name: my-app
spec:
  replicas: 5
  strategy:
    type: RollingUpdate  # ← thay bằng canary config
  template: ...
```

```yaml
# Rollout (Argo Rollouts)
apiVersion: argoproj.io/v1alpha1
kind: Rollout             # ← CRD mới
metadata:
  name: my-app
spec:
  replicas: 5
  strategy:
    canary:               # ← chiến lược canary
      steps:
        - setWeight: 10   # 10% traffic đến canary
        - pause: {}       # Dừng, chờ manual promote hoặc analysis
        - setWeight: 30
        - pause: {duration: 10m}  # Chờ 10 phút
        - setWeight: 50
        - pause: {duration: 10m}
        - setWeight: 100  # Promote hoàn toàn
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
        - name: my-app
          image: my-app:v1
          ports:
            - containerPort: 8080
```

#### Canary với AnalysisTemplate (Auto Analysis)

```yaml
# rollout/my-app-rollout.yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: my-app
  namespace: my-app
spec:
  replicas: 5
  revisionHistoryLimit: 3
  selector:
    matchLabels:
      app: my-app
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
        - name: my-app
          image: my-app:v2
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
  strategy:
    canary:
      # Tham chiếu AnalysisTemplate — chạy sau mỗi step
      analysis:
        templates:
          - templateName: success-rate-analysis
          - templateName: latency-analysis
        startingStep: 1   # Bắt đầu analysis từ step 1 (sau 10%)
        args:
          - name: service-name
            value: my-app-svc
      steps:
        - setWeight: 10    # Step 0: 10% traffic đến v2
        - pause: {duration: 5m}   # Chờ 5 phút để analysis chạy
        - setWeight: 30    # Step 2: 30% traffic
        - pause: {duration: 10m}
        - setWeight: 50
        - pause: {duration: 10m}
        - setWeight: 80
        - pause: {duration: 10m}
        # Step cuối: promote tự động (100%)
```

---

### 4. AnalysisTemplate — Metric-driven Gates ⭐

**AnalysisTemplate** định nghĩa các metric query để đánh giá xem canary có "healthy" không.

#### AnalysisTemplate: Success Rate

```yaml
# rollout/analysis-template-success-rate.yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: success-rate-analysis
  namespace: my-app
spec:
  args:
    - name: service-name   # Nhận argument từ Rollout

  metrics:
    - name: success-rate
      # Chạy query mỗi 2 phút, trong 10 phút
      interval: 2m
      count: 5              # Chạy 5 lần (= 10 phút)
      successCondition: result[0] >= 0.95    # Phải >= 95% thành công
      failureLimit: 2       # Cho phép fail tối đa 2 lần

      provider:
        prometheus:
          address: http://prometheus:9090
          query: |
            sum(rate(http_requests_total{
              status!~"5..",
              service="{{args.service-name}}"
            }[2m])) /
            sum(rate(http_requests_total{
              service="{{args.service-name}}"
            }[2m]))
```

#### AnalysisTemplate: P99 Latency

```yaml
# rollout/analysis-template-latency.yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: latency-analysis
  namespace: my-app
spec:
  args:
    - name: service-name

  metrics:
    - name: p99-latency
      interval: 2m
      count: 5
      # P99 latency phải dưới 500ms
      successCondition: result[0] <= 0.5
      failureLimit: 1   # Chỉ cho phép fail 1 lần (latency nghiêm trọng hơn)

      provider:
        prometheus:
          address: http://prometheus:9090
          query: |
            histogram_quantile(0.99,
              sum(rate(http_request_duration_seconds_bucket{
                service="{{args.service-name}}"
              }[2m])) by (le)
            )
```

#### AnalysisTemplate: Burn Rate Integration ⭐

```yaml
# rollout/analysis-template-burn-rate.yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: burn-rate-analysis
  namespace: my-app
spec:
  args:
    - name: service-name

  metrics:
    - name: error-budget-burn-rate
      interval: 5m
      count: 3
      # Burn rate không được vượt quá 2x
      # (phát hiện trend xấu sớm hơn threshold 14.4x của alert production)
      successCondition: result[0] <= 2
      failureLimit: 1

      provider:
        prometheus:
          address: http://prometheus:9090
          query: |
            # Tính burn rate: (1 - availability) / error_budget
            # SLO target = 99.9% → error_budget = 0.001
            (
              1 - (
                sum(rate(http_requests_total{status!~"5..",service="{{args.service-name}}"}[5m])) /
                sum(rate(http_requests_total{service="{{args.service-name}}"}[5m]))
              )
            ) / 0.001
```

---

### 5. Abort Criteria — Auto-Abort khi Metric xấu

#### Cách Argo Rollouts quyết định abort

```
Analysis kết quả:
  ├── Inconclusive → tiếp tục pause, chờ thêm data
  ├── Success → tự động tiếp tục step tiếp theo
  ├── Failure (vượt failureLimit) → ABORT + ROLLBACK ← auto-abort!
  └── Error (query lỗi) → tuỳ config (mặc định: Inconclusive)
```

#### Thêm abort condition tường minh

```yaml
# Trong AnalysisTemplate, thêm failureCondition
metrics:
  - name: success-rate
    interval: 2m
    count: 5
    successCondition: result[0] >= 0.95
    failureCondition: result[0] < 0.80   # Abort NGAY nếu < 80%
    failureLimit: 0    # Không cho phép fail lần nào
    provider:
      prometheus:
        address: http://prometheus:9090
        query: |
          sum(rate(http_requests_total{status!~"5.."}[2m])) /
          sum(rate(http_requests_total[2m]))
```

#### Xem trạng thái Rollout

```bash
# Xem status rollout
kubectl argo rollouts get rollout my-app -n my-app --watch

# Output ví dụ:
# Name:            my-app
# Namespace:       my-app
# Status:          ॥ Paused
# Strategy:        Canary
# Step:            1/8
# SetWeight:       10
# ActualWeight:    10
# 
# Canary Rollout:  5 of 5 pods (10% canary)
#   Active Service: my-app-svc (stable)
#
# AnalysisRun:     success-rate-analysis-xxxxx
#   Status:        Running
#   Metrics:
#     success-rate: Running (2/5 measurements)
```

```bash
# Promote thủ công (khi analysis pass, tiếp tục step tiếp theo)
kubectl argo rollouts promote my-app -n my-app

# Abort thủ công
kubectl argo rollouts abort my-app -n my-app

# Rollback về stable version
kubectl argo rollouts undo my-app -n my-app
```

---

### 6. Tích hợp với ArgoCD (GitOps + Progressive Delivery)

```
Git commit (new image tag)
    ↓
ArgoCD detect OutOfSync
    ↓
ArgoCD sync → apply Rollout manifest
    ↓
Argo Rollouts controller thực thi canary steps
    ↓
AnalysisRun chạy Prometheus queries
    ↓
Success → promote | Failure → abort + rollback
    ↓ (nếu abort)
Rollout về stable revision (vẫn GitOps compliant)
```

#### Lưu ý khi dùng ArgoCD + Argo Rollouts

```yaml
# Cần ignore diff của các field Argo Rollouts tự quản lý
# Trong ArgoCD Application:
spec:
  ignoreDifferences:
    - group: argoproj.io
      kind: Rollout
      jsonPointers:
        - /spec/replicas           # ArgoCD không override replica count
        - /status                  # Status field
```

---

### 7. Flagger — Alternative đến Argo Rollouts

| Tiêu chí | Argo Rollouts | Flagger |
|---|---|---|
| **CRD** | `Rollout` (thay Deployment) | Dùng native `Deployment`, thêm `Canary` CRD |
| **Traffic control** | Argo native, tích hợp Istio/Nginx | Istio, Nginx, Linkerd, App Mesh |
| **Analysis** | `AnalysisTemplate` | `MetricTemplate` |
| **Tích hợp GitOps** | Tốt với ArgoCD | Tốt với Flux |
| **Learning curve** | Trung bình | Thấp (Deployment không đổi) |
| **Phổ biến** | ⭐⭐⭐ Rất phổ biến | ⭐⭐ Phổ biến |

---

### 8. Load Testing với k6 — Validate trong Lab

```javascript
// k6/load-test.js
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '1m', target: 20 },    // Ramp up đến 20 users
    { duration: '5m', target: 20 },    // Giữ 5 phút
    { duration: '1m', target: 0 },     // Ramp down
  ],
  thresholds: {
    // Fail nếu p99 latency > 500ms
    'http_req_duration{percentile:99}': ['p(99)<500'],
    // Fail nếu error rate > 5%
    'http_req_failed': ['rate<0.05'],
  },
};

export default function () {
  const res = http.get('http://my-app-svc/api/health');
  check(res, {
    'status is 200': (r) => r.status === 200,
    'response time < 200ms': (r) => r.timings.duration < 200,
  });
  sleep(1);
}
```

```bash
# Chạy load test trong khi canary đang deploy
k6 run k6/load-test.js

# Chạy với output về Prometheus (real-time metrics)
k6 run --out experimental-prometheus-rw k6/load-test.js
```

---

### 9. Quy trình Lab cuối tuần (T5–T6)

#### Mục tiêu Lab: "GitOps-ify W8 platform + bolt-on observability + canary"

**Bước 1: GitOps-ify (D1 skills)**
```bash
# 1. Cài ArgoCD vào cluster W8
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 2. Commit tất cả manifest W8 vào Git (nếu chưa có)
# 3. Tạo ArgoCD Application trỏ vào repo
# 4. Xóa manual apply → để ArgoCD sync
```

**Bước 2: Observability (D2 skills)**
```bash
# Dùng kube-prometheus-stack (Helm chart bao gồm Prometheus + Grafana + AlertManager)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kube-prom-stack prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f observability/values.yaml

# Cài Loki stack
helm repo add grafana https://grafana.github.io/helm-charts
helm install loki grafana/loki-stack \
  -n monitoring \
  --set grafana.enabled=false  # Dùng Grafana đã cài
```

**Bước 3: Canary (D3 skills)**
```bash
# Cài Argo Rollouts
kubectl apply -n argo-rollouts \
  -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

# Convert Deployment → Rollout
# Deploy AnalysisTemplate
# Test canary với load test
```

---

## 🔗 Tài liệu tham khảo

| Tài liệu | Link | Ưu tiên |
|---|---|---|
| Argo Rollouts Concepts | https://argoproj.github.io/argo-rollouts/concepts | ⭐⭐⭐ Đọc trước |
| Argo Rollouts Analysis | https://argoproj.github.io/argo-rollouts/features/analysis | ⭐⭐⭐ Cốt lõi |
| Argo Rollouts + ArgoCD | https://argoproj.github.io/argo-rollouts/features/argocd | ⭐⭐⭐ Tích hợp |
| k6 Getting Started | https://k6.io/docs/get-started/running-k6 | ⭐⭐ Lab |
| Flagger Docs | https://flagger.app | ⭐ Tham khảo |
| CNCF Progressive Delivery | https://www.cncf.io/blog/2024/01/26/progressive-delivery | ⭐ Nền tảng |

---

## 🏗️ Cấu trúc thư mục thực hành

```
cloud/w9/day-c/
├── rollout/
│   ├── my-app-rollout.yaml          # Rollout CRD (thay Deployment)
│   ├── my-app-service.yaml          # Service (stable + canary)
│   └── analysis-templates/
│       ├── success-rate.yaml        # AnalysisTemplate: success rate
│       ├── latency.yaml             # AnalysisTemplate: p99 latency
│       └── burn-rate.yaml           # AnalysisTemplate: burn rate
└── k6/
    └── load-test.js                 # Load test script
```

---

## ✅ Checklist tự kiểm tra

- [ ] Phân biệt được 4 deployment strategies: Recreate / Rolling / Blue-Green / Canary
- [ ] Giải thích tại sao dùng Canary thay Rolling Update cho production
- [ ] Viết Rollout CRD với 4 canary steps (10% → 30% → 50% → 100%)
- [ ] Viết AnalysisTemplate với Prometheus query
- [ ] Hiểu `successCondition` vs `failureCondition` vs `failureLimit`
- [ ] Giải thích cách Argo Rollouts auto-abort khi metric fail
- [ ] Tích hợp burn rate từ D2 vào abort criteria
- [ ] Biết cách dùng `kubectl argo rollouts` CLI: get, promote, abort, undo
- [ ] Hiểu cách ArgoCD + Argo Rollouts hoạt động cùng nhau

---

## 📝 Chuẩn bị cho Online Test 1 (17h–18h hôm nay)

**Scope: D1 (GitOps & CI/CD) + D2 (Observability)**

### Ôn tập nhanh D1:
- [ ] 4 nguyên tắc GitOps
- [ ] ArgoCD vs Flux: pull model, CRD khác nhau
- [ ] App-of-Apps pattern
- [ ] Sync waves annotation
- [ ] `git revert` vs `kubectl rollout undo` — cái nào dùng với GitOps?

### Ôn tập nhanh D2:
- [ ] SLI / SLO / SLA / Error Budget — công thức tính
- [ ] 3 pillars: Metrics (Prometheus) / Logs (Loki) / Traces (Jaeger)
- [ ] OTel: SDK → Collector → Backend
- [ ] Multi-window burn rate: Fast (5m/1h) × 14.4x + Slow (30m/6h) × 6x
- [ ] Tại sao dùng 2 window thay vì 1?

---

## 📝 Ghi chú cá nhân

**Câu hỏi / Vướng mắc:**

**Điểm đã hiểu rõ:**

**Kế hoạch thực hành Lab (T5–T6):**
