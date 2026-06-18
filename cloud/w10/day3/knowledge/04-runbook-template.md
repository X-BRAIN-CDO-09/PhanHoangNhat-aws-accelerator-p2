# 04 — Runbook Template

> **Scope:** Runbook structure, incident response steps, common runbooks, automation hooks

---

## 1. Runbook là gì?

**Runbook** = tài liệu hướng dẫn **step-by-step** để xử lý một incident hoặc operational task. Mục tiêu: **bất kỳ ai on-call** cũng có thể follow và resolve.

```
Alert fires: "High CPU on myapp"
        │
        ▼
On-call engineer (có thể là junior)
        │
        ▼
Mở runbook "high-cpu-alert.md"
        │
        ▼
Follow steps 1→2→3→4→5
        │
        ▼
Incident resolved ✅
(Không cần senior, không cần "kinh nghiệm")
```

---

## 2. Runbook Template

```markdown
# Runbook: [Tên Alert / Incident]

> **Severity:** P1/P2/P3/P4
> **Owner:** [team/person]
> **Last Updated:** [date]
> **Alert Source:** [Prometheus rule / CloudWatch alarm / PagerDuty]

---

## 1. Tóm tắt

[1-2 câu mô tả alert/incident là gì, tại sao nó quan trọng]

## 2. Impact

- **User-facing:** [Có/Không] — [mô tả impact nếu có]
- **Data loss risk:** [Có/Không]
- **SLA violation:** [Có/Không] — [SLA nào]

## 3. Prerequisites

- [ ] Access vào cluster: `kubectl` configured
- [ ] Grafana dashboard: [link]
- [ ] Log aggregation: [Loki/CloudWatch link]
- [ ] Escalation contact: [person/channel]

## 4. Diagnosis Steps

### Step 1: Verify alert
```bash
# Kiểm tra alert đang active
[command]
```

**Expected output:** [mô tả]
**If not matching:** → [action / escalate]

### Step 2: Check affected resources
```bash
[command]
```

### Step 3: Identify root cause
```bash
[command]
```

## 5. Resolution Steps

### Option A: [Resolution 1]
```bash
[commands]
```

### Option B: [Resolution 2 — nếu Option A không work]
```bash
[commands]
```

## 6. Verify Resolution

```bash
# Confirm alert resolved
[command]

# Confirm service healthy
[command]
```

## 7. Post-incident

- [ ] Document root cause trong incident ticket
- [ ] Create JIRA cho permanent fix (nếu workaround)
- [ ] Update runbook nếu steps sai/thiếu
- [ ] Schedule postmortem nếu P1/P2

## 8. Escalation

| Level | Contact | When |
|---|---|---|
| L1 | On-call SRE | First responder |
| L2 | Senior SRE | After 15 min, no resolution |
| L3 | Engineering Manager | After 30 min, user impact |

## 9. Related

- [Link to architecture diagram]
- [Link to similar incidents]
- [Link to monitoring dashboard]
```

---

## 3. Runbook: Pod CrashLoopBackOff

```markdown
# Runbook: Pod CrashLoopBackOff

> **Severity:** P2 (staging) / P1 (production)
> **Owner:** Platform team
> **Alert:** `KubePodCrashLooping` (Prometheus)

---

## 1. Tóm tắt

Pod liên tục crash và restart. Kubernetes tăng backoff delay (10s → 20s → 40s → ... → 5min max). Service degraded hoặc unavailable.

## 2. Impact

- **User-facing:** Có nếu production + no healthy replicas
- **Data loss risk:** Có nếu StatefulSet với local data
- **SLA violation:** Có nếu toàn bộ replicas crash

## 3. Diagnosis Steps

### Step 1: Identify crashing pods

```bash
# List pods in CrashLoopBackOff
kubectl get pods -n <namespace> | grep CrashLoop

# Get pod details
kubectl describe pod <pod-name> -n <namespace>
```

**Check:** `Last State` → `Reason` (OOMKilled, Error, ContainerCannotRun)

### Step 2: Check logs

```bash
# Current container logs (may be empty if crash immediately)
kubectl logs <pod-name> -n <namespace>

# Previous container logs (QUAN TRỌNG — logs trước khi crash)
kubectl logs <pod-name> -n <namespace> --previous

# All containers in pod
kubectl logs <pod-name> -n <namespace> --all-containers --previous
```

### Step 3: Check events

```bash
kubectl get events -n <namespace> --sort-by=.metadata.creationTimestamp | tail -20
```

### Step 4: Identify cause

| Reason | Root Cause | Fix |
|---|---|---|
| **OOMKilled** | Container dùng quá memory limit | Tăng memory limit hoặc fix memory leak |
| **Error** (exit code 1) | Application error | Check logs → fix code |
| **Error** (exit code 137) | SIGKILL (OOM hoặc eviction) | Check memory, node pressure |
| **ContainerCannotRun** | Image not found, wrong entrypoint | Check image tag, Dockerfile |
| **CreateContainerConfigError** | Missing ConfigMap/Secret | Check CM/Secret exists |

## 4. Resolution Steps

### Option A: OOMKilled → Tăng memory limit

```bash
# Check current limits
kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.containers[*].resources}'

# Patch deployment
kubectl patch deployment <deploy> -n <ns> -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"<container>","resources":{"limits":{"memory":"1Gi"}}}]}}}}'
```

### Option B: Application Error → Rollback

```bash
# Check deployment history
kubectl rollout history deployment/<deploy> -n <ns>

# Rollback to previous revision
kubectl rollout undo deployment/<deploy> -n <ns>

# Verify
kubectl rollout status deployment/<deploy> -n <ns>
```

### Option C: Missing ConfigMap/Secret

```bash
# Check what CM/Secrets pod needs
kubectl describe pod <pod> -n <ns> | grep -A5 "Environment\|Volumes"

# Verify they exist
kubectl get configmap <name> -n <ns>
kubectl get secret <name> -n <ns>
```

## 5. Verify Resolution

```bash
# Confirm pod running
kubectl get pods -n <ns> -l app=<app> -w

# Confirm no more CrashLoop
kubectl get events -n <ns> --field-selector reason=BackOff | tail -5
# → Should be no recent events
```
```

---

## 4. Runbook: Node Not Ready

```markdown
# Runbook: Node NotReady

> **Severity:** P2
> **Alert:** `KubeNodeNotReady` (Prometheus)

## Diagnosis

```bash
# Step 1: List node status
kubectl get nodes
kubectl describe node <node-name>

# Step 2: Check node conditions
kubectl get node <node> -o jsonpath='{range .status.conditions[*]}{.type}{"\t"}{.status}{"\t"}{.reason}{"\n"}{end}'

# Step 3: Check kubelet
# SSH vào node (nếu có access)
systemctl status kubelet
journalctl -u kubelet -n 100

# Step 4: Check resources
kubectl describe node <node> | grep -A5 "Allocated resources"
# DiskPressure, MemoryPressure, PIDPressure?
```

## Resolution

```bash
# Option A: Cordon + Drain (graceful)
kubectl cordon <node>     # No new pods scheduled
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data

# Option B: ASG replacement (EKS)
# Terminate instance → ASG launch new one
aws autoscaling terminate-instance-in-auto-scaling-group \
  --instance-id <instance-id> \
  --should-decrement-desired-capacity false

# Option C: Restart kubelet
# SSH vào node
sudo systemctl restart kubelet
```
```

---

## 5. Runbook: High CPU Alert

```markdown
# Runbook: High CPU Alert

> **Severity:** P3
> **Alert:** `HighCPUUsage` (> 80% for 10 min)

## Diagnosis

```bash
# Step 1: Which pods use most CPU?
kubectl top pods -n <ns> --sort-by=cpu

# Step 2: Check HPA
kubectl get hpa -n <ns>
kubectl describe hpa <name> -n <ns>

# Step 3: Check if HPA max reached
# CurrentReplicas == MaxReplicas? → Need to increase max or optimize
```

## Resolution

```bash
# Option A: HPA đang scale, wait
# Nếu CurrentReplicas < MaxReplicas → HPA đang xử lý

# Option B: Increase HPA max
kubectl patch hpa <name> -n <ns> -p '{"spec":{"maxReplicas": 10}}'

# Option C: Optimize application
# Profile app, identify bottleneck
# → Long-term fix ticket
```
```

---

## 6. Runbook: Secret Rotation Failure

```markdown
# Runbook: Secret Rotation Failure (ESO)

> **Severity:** P2
> **Alert:** `ExternalSecretSyncFailed`

## Diagnosis

```bash
# Step 1: Check ExternalSecret status
kubectl get externalsecret -A
kubectl describe externalsecret <name> -n <ns>
# → Check Events + Status.Conditions

# Step 2: Check ESO logs
kubectl logs -n external-secrets deployment/external-secrets --tail=50

# Step 3: Check AWS Secrets Manager
aws secretsmanager get-secret-value --secret-id <secret-name>
# → AccessDeniedException? Secret deleted?
```

## Resolution

```bash
# Option A: IAM permission issue
# Check IRSA role annotations
kubectl get sa -n external-secrets external-secrets -o yaml | grep role-arn

# Verify role
aws sts assume-role-with-web-identity --role-arn <arn> ...

# Option B: Secret deleted/renamed in AWS
# Recreate or update ExternalSecret remoteRef.key

# Option C: ESO restart
kubectl rollout restart deployment/external-secrets -n external-secrets
```
```

---

## 7. Automating Runbooks

### Link alerts → runbooks

```yaml
# PrometheusRule with runbook_url
groups:
  - name: platform
    rules:
      - alert: KubePodCrashLooping
        expr: rate(kube_pod_container_status_restarts_total[5m]) > 0
        for: 15m
        annotations:
          runbook_url: "https://github.com/myorg/platform/blob/main/runbooks/pod-crashloop.md"
          summary: "Pod {{ $labels.pod }} in {{ $labels.namespace }} is crash looping"
        labels:
          severity: warning
```

### AlertManager → Slack with runbook link

```yaml
# alertmanager.yaml
receivers:
  - name: slack
    slack_configs:
      - channel: '#alerts'
        title: '{{ .CommonAnnotations.summary }}'
        text: |
          *Severity:* {{ .CommonLabels.severity }}
          *Namespace:* {{ .CommonLabels.namespace }}
          *Runbook:* {{ .CommonAnnotations.runbook_url }}
```

---

## 8. Postmortem Template (Google SRE)

```markdown
# Postmortem: [Incident Title]

## Date: [YYYY-MM-DD]
## Duration: [start — end]
## Severity: P[1-4]
## Author: [name]

## Summary
[1-2 câu]

## Impact
- Users affected: [number]
- Duration of impact: [time]
- Revenue impact: [if applicable]

## Root Cause
[Technical explanation]

## Timeline (UTC+7)
| Time | Event |
|---|---|
| 14:00 | Alert fired: ... |
| 14:05 | On-call acknowledged |
| 14:15 | Root cause identified |
| 14:30 | Fix deployed |
| 14:35 | Alert resolved |

## Action Items

| Action | Owner | Priority | Ticket |
|---|---|---|---|
| Fix X | Alice | P1 | JIRA-123 |
| Add monitoring for Y | Bob | P2 | JIRA-124 |
| Update runbook | Carol | P3 | JIRA-125 |

## Lessons Learned
### What went well
### What went wrong  
### Where we got lucky
```
