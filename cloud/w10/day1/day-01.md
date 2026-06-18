# W10 — D1: RBAC + Admission Policy (OPA/Gatekeeper)

> **Ngày:** T2 15/06/2026 | **Theme:** Secure & Operate
> **Commit prefix:** `[W10-D1]`

---

## 🎯 Mục tiêu học tập

Sau ngày hôm nay, bạn có thể:

- [ ] Phân biệt Role / ClusterRole / RoleBinding / ClusterRoleBinding và khi nào dùng gì
- [ ] Tạo RBAC cho 3 nhóm: `developer`, `sre`, `viewer` với least-privilege
- [ ] Dùng `kubectl auth can-i` để verify quyền trước khi deploy
- [ ] Giải thích OPA Rego basics và viết policy đơn giản
- [ ] Phân biệt Gatekeeper ConstraintTemplate vs Constraint
- [ ] Hiểu ValidatingAdmissionPolicy (native K8s 1.30+) và khi nào dùng thay Gatekeeper
- [ ] Phân biệt audit mode vs enforce mode và chiến lược rollout policy

---

## 📚 Kiến thức trọng tâm

### Tổng quan — Security ở Cluster Level

```
Request flow khi user gửi lệnh tới K8s API Server:

User/kubectl
    │
    ▼
┌──────────────────────────────────────────────────────────────┐
│                    K8s API Server                              │
│                                                                │
│  1. Authentication ──► "Bạn là ai?"                           │
│       (Certificate, Token, OIDC, ServiceAccount)               │
│                                                                │
│  2. Authorization ──► "Bạn được làm gì?" (RBAC)              │
│       (Role, ClusterRole, Binding)                             │
│                                                                │
│  3. Admission Control ──► "Object có hợp lệ không?"          │
│       ├── Mutating Webhooks (sửa object)                      │
│       └── Validating Webhooks (chặn object) ← OPA/Gatekeeper │
│                                                                │
│  4. Persist to etcd                                           │
└──────────────────────────────────────────────────────────────┘
```

### Chi tiết từng topic

| # | File kiến thức | Nội dung |
|---|---|---|
| 1 | [01-rbac-fundamentals.md](knowledge/01-rbac-fundamentals.md) | Role, ClusterRole, RoleBinding, ClusterRoleBinding, ServiceAccount, `kubectl auth can-i` |
| 2 | [02-rbac-practical-patterns.md](knowledge/02-rbac-practical-patterns.md) | 3-role pattern (developer/sre/viewer), namespace isolation, aggregated ClusterRoles |
| 3 | [03-opa-rego-basics.md](knowledge/03-opa-rego-basics.md) | OPA architecture, Rego language, playground, policy testing |
| 4 | [04-gatekeeper.md](knowledge/04-gatekeeper.md) | Gatekeeper install, ConstraintTemplate vs Constraint, audit vs enforce, library |
| 5 | [05-validating-admission-policy.md](knowledge/05-validating-admission-policy.md) | Native K8s 1.30+ ValidatingAdmissionPolicy, CEL expressions, so sánh với Gatekeeper |
| 6 | [06-admission-policy-strategy.md](knowledge/06-admission-policy-strategy.md) | Rollout strategy, audit→warn→enforce, monitoring violations, exception handling |

---

## 🔗 Tài liệu tham khảo

| Tài liệu | Link | Ưu tiên |
|---|---|---|
| K8s RBAC Official Docs | https://kubernetes.io/docs/reference/access-authn-authz/rbac | ⭐⭐⭐ Đọc trước |
| OPA Rego Language | https://www.openpolicyagent.org/docs/latest/policy-language | ⭐⭐⭐ Quan trọng |
| Gatekeeper Docs | https://open-policy-agent.github.io/gatekeeper/website/docs | ⭐⭐⭐ Thực hành |
| ValidatingAdmissionPolicy | https://kubernetes.io/docs/reference/access-authn-authz/validating-admission-policy | ⭐⭐ Cần biết |
| Gatekeeper Policy Library | https://open-policy-agent.github.io/gatekeeper-library/website | ⭐⭐ Thực hành |
| K8s Pod Security Standards | https://kubernetes.io/docs/concepts/security/pod-security-standards | ⭐ Nâng cao |

---

## 🏗️ Cấu trúc thư mục thực hành

```
cloud/w10/day1/
├── day-01.md                         # File này
├── knowledge/
│   ├── 01-rbac-fundamentals.md
│   ├── 02-rbac-practical-patterns.md
│   ├── 03-opa-rego-basics.md
│   ├── 04-gatekeeper.md
│   ├── 05-validating-admission-policy.md
│   └── 06-admission-policy-strategy.md
├── rbac/
│   ├── roles/
│   │   ├── developer-role.yaml
│   │   ├── sre-clusterrole.yaml
│   │   └── viewer-clusterrole.yaml
│   ├── bindings/
│   │   ├── developer-binding.yaml
│   │   ├── sre-binding.yaml
│   │   └── viewer-binding.yaml
│   └── serviceaccounts/
│       └── ci-sa.yaml
└── policies/
    ├── constraint-templates/
    │   ├── require-labels.yaml
    │   ├── block-privileged.yaml
    │   ├── require-resource-limits.yaml
    │   └── allowed-repos.yaml
    └── constraints/
        ├── require-team-label.yaml
        ├── block-privileged-pods.yaml
        ├── require-limits.yaml
        └── allowed-registries.yaml
```

---

## ✅ Checklist tự kiểm tra

- [ ] Phân biệt Role vs ClusterRole — scope namespace vs cluster-wide
- [ ] Tạo 3 role (developer/sre/viewer) với quyền chính xác
- [ ] Dùng `kubectl auth can-i --as=system:serviceaccount:dev:ci-deployer -- create deployments -n dev`
- [ ] Viết 1 Rego policy cơ bản: require label "team" trên mọi Deployment
- [ ] Install Gatekeeper, tạo ConstraintTemplate + Constraint
- [ ] Deploy constraint ở audit mode → kiểm tra violations → chuyển enforce
- [ ] Viết ValidatingAdmissionPolicy (CEL) block container chạy root
- [ ] So sánh Gatekeeper vs ValidatingAdmissionPolicy — ưu nhược

---

## 📝 Ghi chú cá nhân

<!-- Ghi lại những điểm khó hiểu, câu hỏi cần hỏi mentor -->

**Câu hỏi / Vướng mắc:**

**Điểm đã hiểu rõ:**

**Kế hoạch thực hành:**
