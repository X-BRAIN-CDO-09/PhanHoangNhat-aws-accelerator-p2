# W10 — D3: Platform Integration + Runbook + Cost Guard

> **Ngày:** T4 17/06/2026 | **Theme:** Secure & Operate
> **Commit prefix:** `[W10-D3]`

---

## 🎯 Mục tiêu học tập

Sau ngày hôm nay, bạn có thể:

- [ ] Tích hợp toàn bộ stack W8→W10 thành mini platform end-to-end
- [ ] Cấu hình ResourceQuota + LimitRange cho namespace isolation
- [ ] Chạy chaos test cơ bản (pod kill, network partition)
- [ ] Viết runbook template cho incident response
- [ ] Thiết lập AWS Cost Anomaly Detection
- [ ] Deploy fresh cluster với toàn bộ platform components trong < 2h

---

## 📚 Kiến thức trọng tâm

### Tổng quan — Platform End-to-End

```
W8 (Foundation)        W9 (Delivery)          W10 (Secure & Operate)
┌─────────────┐       ┌─────────────┐         ┌─────────────────────┐
│ EKS Cluster │       │ ArgoCD      │         │ RBAC (3 roles)      │
│ Terraform   │──────►│ GitOps      │────────►│ Gatekeeper (4 cstr) │
│ Networking  │       │ Helm Charts │         │ ESO (secrets)       │
│ Ingress     │       │ Canary      │         │ Cosign (signing)    │
└─────────────┘       └──────┬──────┘         │ ResourceQuota       │
                             │                │ Runbook             │
┌─────────────┐             │                │ Cost Guard          │
│ Prometheus  │◄────────────┘                └─────────────────────┘
│ Grafana     │
│ AlertManager│        → Mini Platform End-to-End
│ Loki        │          "GitOps + Observability + Canary + Security"
└─────────────┘          Deploy < 2h từ repo lên fresh cluster
```

### Chi tiết từng topic

| # | File kiến thức | Nội dung |
|---|---|---|
| 1 | [01-platform-integration.md](knowledge/01-platform-integration.md) | Tích hợp stack W8→W10, bootstrap script, dependency order |
| 2 | [02-resource-quota-limitrange.md](knowledge/02-resource-quota-limitrange.md) | ResourceQuota, LimitRange, namespace budget, defaults |
| 3 | [03-chaos-testing.md](knowledge/03-chaos-testing.md) | Chaos engineering principles, Litmus/Chaos Mesh, pod kill, network chaos |
| 4 | [04-runbook-template.md](knowledge/04-runbook-template.md) | Runbook template, incident response steps, automation hooks |
| 5 | [05-aws-cost-anomaly-detection.md](knowledge/05-aws-cost-anomaly-detection.md) | Cost Anomaly Detection, Budget alerts, cost allocation tags |

---

## 🔗 Tài liệu tham khảo

| Tài liệu | Link | Ưu tiên |
|---|---|---|
| K8s ResourceQuota | https://kubernetes.io/docs/concepts/policy/resource-quotas | ⭐⭐⭐ Đọc trước |
| K8s LimitRange | https://kubernetes.io/docs/concepts/policy/limit-range | ⭐⭐⭐ Quan trọng |
| Litmus Chaos Engineering | https://litmuschaos.io/docs | ⭐⭐ Thực hành |
| Chaos Mesh | https://chaos-mesh.org/docs | ⭐⭐ Alternative |
| Google SRE Workbook — Postmortem | https://sre.google/workbook/postmortem-culture | ⭐⭐⭐ Quan trọng |
| AWS Cost Anomaly Detection | https://docs.aws.amazon.com/cost-management/latest/userguide/manage-ad.html | ⭐⭐ Cần biết |

---

## 🏗️ Cấu trúc thư mục thực hành

```
cloud/w10/day3/
├── day-03.md                         # File này
├── knowledge/
│   ├── 01-platform-integration.md
│   ├── 02-resource-quota-limitrange.md
│   ├── 03-chaos-testing.md
│   ├── 04-runbook-template.md
│   └── 05-aws-cost-anomaly-detection.md
├── platform-bootstrap/
│   ├── 00-namespaces.yaml
│   ├── 01-rbac.yaml
│   ├── 02-gatekeeper.yaml
│   ├── 03-eso.yaml
│   ├── 04-quotas.yaml
│   └── bootstrap.sh
├── runbooks/
│   ├── pod-crashloop.md
│   ├── node-not-ready.md
│   ├── high-cpu-alert.md
│   └── secret-rotation-failure.md
└── cost/
    ├── cost-anomaly.tf
    └── budget-alerts.tf
```

---

## ✅ Checklist tự kiểm tra

- [ ] Liệt kê dependency order khi bootstrap cluster: namespace → RBAC → Gatekeeper → ESO → quotas → apps
- [ ] Tạo ResourceQuota giới hạn: 10 pods, 4 CPU, 8Gi memory cho namespace
- [ ] Tạo LimitRange với default requests/limits cho containers
- [ ] Chạy chaos test: kill 1 pod → verify HPA tạo pod mới < 30s
- [ ] Viết runbook cho "Pod CrashLoopBackOff" — 5 bước debug
- [ ] Thiết lập AWS Cost Anomaly Detection với SNS alert
- [ ] Chạy bootstrap script: fresh namespace → all platform components < 30 phút

---

## 📝 Ghi chú cá nhân

<!-- Ghi lại những điểm khó hiểu, câu hỏi cần hỏi mentor -->

**Câu hỏi / Vướng mắc:**

**Điểm đã hiểu rõ:**

**Kế hoạch thực hành:**
