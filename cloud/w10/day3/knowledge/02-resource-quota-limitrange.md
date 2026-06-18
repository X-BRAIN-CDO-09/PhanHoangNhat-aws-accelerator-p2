# 02 — ResourceQuota + LimitRange

> **Scope:** Namespace resource budgeting, container defaults, multi-tenant isolation

---

## 1. Tại sao cần ResourceQuota + LimitRange?

```
Without quotas:
  Team A deploys 100 replicas → eats all cluster resources
  Team B's pods: Pending... Pending... Pending...
  → "Noisy neighbor" problem

With quotas:
  Team A namespace: max 20 pods, 8 CPU, 16Gi memory
  Team B namespace: max 20 pods, 8 CPU, 16Gi memory
  → Fair resource sharing, predictable capacity

Without LimitRange:
  Developer deploys pod without limits
  → Pod eats unlimited memory → OOMKill → crash other pods on same node

With LimitRange:
  Default limits auto-injected → every pod has boundaries
```

---

## 2. ResourceQuota — Namespace Budget

### Cú pháp

```yaml
# resource-quota.yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: team-alpha-quota
  namespace: team-alpha
spec:
  hard:
    # === Compute Resources ===
    requests.cpu: "4"                # Tổng CPU requests: 4 cores
    requests.memory: 8Gi             # Tổng memory requests: 8 GiB
    limits.cpu: "8"                  # Tổng CPU limits: 8 cores
    limits.memory: 16Gi             # Tổng memory limits: 16 GiB
    
    # === Object Count ===
    pods: "20"                       # Max 20 pods
    services: "10"                   # Max 10 services
    configmaps: "20"                 # Max 20 configmaps
    secrets: "20"                    # Max 20 secrets
    persistentvolumeclaims: "5"      # Max 5 PVCs
    services.loadbalancers: "2"      # Max 2 LoadBalancers
    services.nodeports: "0"          # NO NodePort (security)
    
    # === Storage ===
    requests.storage: 50Gi           # Tổng storage: 50 GiB
```

### Production-ready Quotas

```yaml
# quotas-production.yaml
---
# Production namespace — generous limits
apiVersion: v1
kind: ResourceQuota
metadata:
  name: production-quota
  namespace: production
spec:
  hard:
    requests.cpu: "16"
    requests.memory: 32Gi
    limits.cpu: "32"
    limits.memory: 64Gi
    pods: "50"
    services: "20"
    services.loadbalancers: "3"
    services.nodeports: "0"
    persistentvolumeclaims: "10"
    requests.storage: 200Gi
---
# Staging namespace — moderate limits
apiVersion: v1
kind: ResourceQuota
metadata:
  name: staging-quota
  namespace: staging
spec:
  hard:
    requests.cpu: "8"
    requests.memory: 16Gi
    limits.cpu: "16"
    limits.memory: 32Gi
    pods: "30"
    services: "10"
    services.loadbalancers: "1"
    services.nodeports: "0"
    persistentvolumeclaims: "5"
    requests.storage: 50Gi
---
# Dev namespace — restricted
apiVersion: v1
kind: ResourceQuota
metadata:
  name: dev-quota
  namespace: dev
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
    pods: "20"
    services: "5"
    services.loadbalancers: "0"      # Không cho phép LB ở dev
    services.nodeports: "0"
    persistentvolumeclaims: "3"
    requests.storage: 20Gi
```

### Kiểm tra quota usage

```bash
# Xem quota và usage hiện tại
kubectl describe resourcequota -n team-alpha

# Output:
# Name:                   team-alpha-quota
# Namespace:              team-alpha
# Resource                Used   Hard
# --------                ----   ----
# configmaps              3      20
# limits.cpu              2      8
# limits.memory           4Gi    16Gi
# pods                    5      20
# requests.cpu            1      4
# requests.memory         2Gi    8Gi
# services                2      10

# Khi vượt quota:
# Error from server (Forbidden): exceeded quota: team-alpha-quota,
# requested: pods=1, used: pods=20, limited: pods=20
```

---

## 3. LimitRange — Container Defaults

LimitRange thiết lập **default** và **min/max** cho containers trong namespace.

```yaml
# limit-range.yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: team-alpha
spec:
  limits:
    # === Container defaults ===
    - type: Container
      default:                       # Default limits (nếu không specify)
        cpu: 500m
        memory: 512Mi
      defaultRequest:                # Default requests
        cpu: 100m
        memory: 128Mi
      min:                           # Minimum allowed
        cpu: 50m
        memory: 64Mi
      max:                           # Maximum allowed
        cpu: "2"
        memory: 2Gi
    
    # === Pod-level limits ===
    - type: Pod
      max:
        cpu: "4"                     # Max CPU per pod (all containers)
        memory: 4Gi
    
    # === PVC limits ===
    - type: PersistentVolumeClaim
      min:
        storage: 1Gi
      max:
        storage: 50Gi
```

### Hành vi của LimitRange

```
Developer deploy pod KHÔNG có resources:
spec:
  containers:
    - name: app
      image: myapp:v1
      # Không có resources block

LimitRange auto-inject:
spec:
  containers:
    - name: app
      image: myapp:v1
      resources:
        requests:
          cpu: 100m              ← defaultRequest
          memory: 128Mi          ← defaultRequest
        limits:
          cpu: 500m              ← default
          memory: 512Mi          ← default

Developer deploy pod VỚI resources vượt max:
spec:
  containers:
    - name: app
      resources:
        limits:
          cpu: "5"               ← Vượt max (2 cores)

→ Error: "cpu max limit exceeded: Limited to 2"
```

---

## 4. ResourceQuota + LimitRange Together

```
ResourceQuota = "Namespace ngân sách bao nhiêu?" (tổng)
LimitRange    = "Mỗi container được bao nhiêu?" (cá nhân)

Cả hai cần đi kèm nhau:
├── ResourceQuota KHÔNG CÓ LimitRange:
│   → Pod không có requests/limits → KHÔNG bị đếm vào quota
│   → Quota vô nghĩa!
│
├── LimitRange KHÔNG CÓ ResourceQuota:
│   → Mỗi pod có limits nhưng KHÔNG giới hạn tổng
│   → 1000 pods x 500m = 500 CPU → vẫn overcommit
│
└── ResourceQuota + LimitRange:
    → Mỗi pod có default limits (LimitRange)
    → Tổng không vượt budget (ResourceQuota)
    → ✅ Đúng cách
```

---

## 5. Priority Classes

Kết hợp với PriorityClass để đảm bảo critical pods không bị evict:

```yaml
# priority-classes.yaml
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: platform-critical
value: 1000000
globalDefault: false
description: "Platform components (monitoring, ingress, security)"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: production-high
value: 100000
globalDefault: false
description: "Production workloads"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: default-priority
value: 0
globalDefault: true                   # Default cho mọi pod không specify
description: "Default priority for regular workloads"
```

### Scoped quota by PriorityClass

```yaml
# Chỉ cho phép 5 pods với priority "production-high"
apiVersion: v1
kind: ResourceQuota
metadata:
  name: high-priority-quota
  namespace: production
spec:
  hard:
    pods: "5"
  scopeSelector:
    matchExpressions:
      - scopeName: PriorityClass
        operator: In
        values: ["production-high"]
```

---

## 6. Monitoring Quota Usage

```bash
# Prometheus metrics
# kube_resourcequota{namespace, resource, type}
# type = "hard" (limit) | "used" (current usage)

# PromQL: % usage
kube_resourcequota{type="used"} / kube_resourcequota{type="hard"} * 100

# Alert khi > 80%
# PrometheusRule:
groups:
  - name: quota-alerts
    rules:
      - alert: NamespaceQuotaNearLimit
        expr: |
          kube_resourcequota{type="used"} / kube_resourcequota{type="hard"} > 0.8
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Namespace {{ $labels.namespace }} đang dùng > 80% quota {{ $labels.resource }}"
```

---

## 7. Common Patterns

### Multi-tenant cluster

```yaml
# Mỗi team 1 namespace với quota riêng
# Template (dùng Kustomize hoặc Helm):
# team-namespace/
# ├── namespace.yaml
# ├── resource-quota.yaml
# ├── limit-range.yaml
# ├── network-policy.yaml
# └── role-binding.yaml
```

### Quota Tiers

| Tier | CPU (req/lim) | Memory (req/lim) | Pods | Use case |
|---|---|---|---|---|
| Small | 2/4 | 4Gi/8Gi | 10 | Dev, sandbox |
| Medium | 8/16 | 16Gi/32Gi | 30 | Staging, small prod |
| Large | 16/32 | 32Gi/64Gi | 50 | Production |
| XLarge | 32/64 | 64Gi/128Gi | 100 | Heavy production |
