# 06 — Admission Policy Strategy

> **Scope:** Rollout strategy (audit → warn → enforce), monitoring violations, exception handling, production playbook

---

## 1. Tại sao cần Strategy?

Deploy policy **enforce ngay từ đầu** = **break mọi thứ**. Workloads cũ vi phạm → bị block → outage.

```
❌ BAD:  Write policy → enforce → "Tại sao app bị block?!"
✅ GOOD: Write policy → audit → fix violations → warn → enforce
```

---

## 2. 4-Phase Rollout Strategy

```
Phase 1: AUDIT (dryrun)     ─── 1-2 tuần ───
    │  • Deploy constraint với enforcementAction: dryrun
    │  • Gatekeeper scan existing resources
    │  • Xuất report: bao nhiêu violations?
    │  • Không block bất kỳ request nào
    │
    ▼
Phase 2: FIX                ─── 1-2 sprint ───
    │  • Fix violations từ audit report
    │  • Update manifests, Helm values, Kustomize
    │  • Violations count giảm dần → 0
    │
    ▼
Phase 3: WARN               ─── 1 tuần ───
    │  • Chuyển enforcementAction: warn
    │  • User thấy warning khi deploy
    │  • Vẫn cho phép, nhưng ghi nhận
    │  • Monitor: còn ai deploy vi phạm?
    │
    ▼
Phase 4: ENFORCE             ─── Permanent ───
       • Chuyển enforcementAction: deny
       • Block requests vi phạm
       • Monitor alerts cho false positives
       • Maintain exception list
```

---

## 3. Phase 1: Audit — Discovery

### Deploy constraints ở dryrun mode

```yaml
# constraint với dryrun
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: require-team-label
  annotations:
    policy.platform.io/phase: audit
    policy.platform.io/owner: platform-team
    policy.platform.io/ticket: SEC-123
spec:
  enforcementAction: dryrun                # ← Chỉ audit, không block
  match:
    kinds:
      - apiGroups: ["apps"]
        kinds: ["Deployment"]
    excludedNamespaces:
      - kube-system
      - gatekeeper-system
  parameters:
    labels: ["team", "env"]
```

### Xuất audit report

```bash
#!/bin/bash
# audit-report.sh — Xuất violation report

echo "============================================"
echo "  Gatekeeper Audit Report — $(date)"
echo "============================================"
echo ""

for constraint_kind in $(kubectl get crd -o name | grep constraints.gatekeeper.sh | sed 's|customresourcedefinition.apiextensions.k8s.io/||' | sed 's|.constraints.gatekeeper.sh||'); do
  for constraint_name in $(kubectl get $constraint_kind -o name 2>/dev/null | sed 's|.*/||'); do
    total=$(kubectl get $constraint_kind $constraint_name -o jsonpath='{.status.totalViolations}' 2>/dev/null)
    enforcement=$(kubectl get $constraint_kind $constraint_name -o jsonpath='{.spec.enforcementAction}' 2>/dev/null)
    
    if [ "$total" -gt 0 ] 2>/dev/null; then
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "📋 $constraint_kind/$constraint_name"
      echo "   Enforcement: $enforcement | Violations: $total"
      echo ""
      
      kubectl get $constraint_kind $constraint_name \
        -o jsonpath='{range .status.violations[*]}  ⚠️  {.kind}/{.namespace}/{.name}: {.message}{"\n"}{end}'
      echo ""
    fi
  done
done

echo "============================================"
echo "  Summary"
echo "============================================"
kubectl get constraints -o wide 2>/dev/null
```

---

## 4. Phase 2: Fix Violations

### Tracking violations over time

```bash
# Prometheus metrics từ Gatekeeper
# gatekeeper_violations (gauge) — số violations hiện tại

# Grafana dashboard query:
# sum(gatekeeper_violations) by (constraint_name)

# Target: violations count → 0 trước khi chuyển warn
```

### Fix patterns

```yaml
# Fix 1: Thêm missing labels
# BEFORE:
metadata:
  name: my-deployment
# AFTER:
metadata:
  name: my-deployment
  labels:
    team: alpha            # ← Thêm
    env: production        # ← Thêm

# Fix 2: Thêm resource limits
# BEFORE:
containers:
  - name: app
    image: my-app:v1
# AFTER:
containers:
  - name: app
    image: my-app:v1
    resources:             # ← Thêm
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 500m
        memory: 512Mi

# Fix 3: Remove privileged
# BEFORE:
securityContext:
  privileged: true
# AFTER:
securityContext:
  privileged: false       # ← Sửa
  runAsNonRoot: true       # ← Thêm
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
```

---

## 5. Phase 3: Warn

```yaml
# Chuyển constraint sang warn
spec:
  enforcementAction: warn          # ← Đổi từ dryrun
```

```bash
# Khi user deploy resource vi phạm, họ thấy:
# Warning: [require-team-label] Deployment 'my-app' thiếu required labels: {"team"}
# deployment.apps/my-app created  ← Vẫn được tạo

# Monitor warnings
kubectl get events --field-selector reason=FailedAdmission
```

---

## 6. Phase 4: Enforce

```yaml
# Chuyển constraint sang deny
spec:
  enforcementAction: deny          # ← Đổi từ warn
```

```bash
# Khi user deploy resource vi phạm:
# Error from server (Forbidden): error when creating "deployment.yaml": 
# admission webhook "validation.gatekeeper.sh" denied the request: 
# [require-team-label] Deployment 'my-app' thiếu required labels: {"team"}
# ← Request bị block
```

---

## 7. Exception Handling

Không phải lúc nào cũng enforce 100%. Cần exception cho:
- System components (kube-system)
- Legacy workloads (migration period)
- Special use cases (monitoring agents cần privileged)

### Pattern 1: Namespace Exclusion

```yaml
spec:
  match:
    excludedNamespaces:
      - kube-system
      - gatekeeper-system
      - monitoring               # Prometheus node-exporter cần privileged
```

### Pattern 2: Image Exemption

```yaml
spec:
  parameters:
    exemptImages:
      - "quay.io/prometheus/node-exporter"
      - "docker.io/calico/"
```

### Pattern 3: Label-based Exemption

```yaml
spec:
  match:
    labelSelector:
      matchExpressions:
        - key: policy.platform.io/exempt
          operator: DoesNotExist     # Chỉ enforce nếu KHÔNG có label exempt
```

```yaml
# Resource được exempt
metadata:
  labels:
    policy.platform.io/exempt: "SEC-456"     # Ticket number bắt buộc
    policy.platform.io/exempt-until: "2024-03-01"  # Có thời hạn
```

### Pattern 4: Exception ADR (Architecture Decision Record)

```markdown
# ADR-2024-001: Prometheus node-exporter privileged exemption

## Status: Approved

## Context
Prometheus node-exporter cần `privileged: true` để mount host filesystem
cho disk/network metrics.

## Decision
Exempt image `quay.io/prometheus/node-exporter` từ K8sBlockPrivileged.

## Consequences
- node-exporter chạy privileged — risk nếu image bị compromise
- Mitigation: Pin version, verify signature, restrict NetworkPolicy

## Review date: 2024-06-01
```

---

## 8. Monitoring & Alerting

### Gatekeeper metrics cho Prometheus

```yaml
# ServiceMonitor cho Gatekeeper
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: gatekeeper
  namespace: gatekeeper-system
spec:
  selector:
    matchLabels:
      gatekeeper.sh/system: "yes"
  endpoints:
    - port: metrics
      interval: 30s
```

### Key Prometheus metrics

```promql
# Số violations hiện tại (audit)
gatekeeper_violations{enforcement_action="deny"}

# Request latency của webhook
gatekeeper_validation_request_duration_seconds_bucket

# Webhook errors
rate(gatekeeper_validation_request_count{admission_status="error"}[5m])
```

### Alert rules

```yaml
# PrometheusRule
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: gatekeeper-alerts
spec:
  groups:
    - name: gatekeeper
      rules:
        # Alert khi có violations mới
        - alert: GatekeeperViolationsDetected
          expr: gatekeeper_violations > 0
          for: 10m
          labels:
            severity: warning
          annotations:
            summary: "{{ $labels.constraint_name }} có {{ $value }} violations"
        
        # Alert khi webhook bị lỗi
        - alert: GatekeeperWebhookErrors
          expr: rate(gatekeeper_validation_request_count{admission_status="error"}[5m]) > 0
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "Gatekeeper webhook errors detected"
```

---

## 9. Production Checklist

```
Policy Rollout Checklist:
├── [ ] Write ConstraintTemplate + unit tests (opa test)
├── [ ] Deploy constraint ở dryrun mode
├── [ ] Wait 1-2 tuần, collect audit data
├── [ ] Generate violations report
├── [ ] Fix all violations (hoặc document exceptions)
├── [ ] Chuyển sang warn mode
├── [ ] Notify teams, set deadline
├── [ ] Wait 1 tuần, monitor warnings
├── [ ] Chuyển sang deny mode
├── [ ] Set up Prometheus alerts
├── [ ] Document exception ADRs
├── [ ] Schedule quarterly review
└── [ ] Add to platform onboarding docs
```
