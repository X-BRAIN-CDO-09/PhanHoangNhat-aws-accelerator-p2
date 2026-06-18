# 02 — RBAC Practical Patterns

> **Scope:** 3-role pattern (developer/sre/viewer), namespace isolation, aggregated ClusterRoles, CI/CD SA

---

## 1. Pattern: 3-Role Team Structure

Đây là **production-ready RBAC** cho team Cloud/DevOps điển hình:

```
┌─────────────────────────────────────────────────────────┐
│                    Cluster Roles                         │
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │   DEVELOPER  │  │     SRE      │  │    VIEWER    │  │
│  │              │  │              │  │              │  │
│  │ • Deploy app │  │ • Full admin │  │ • Read-only  │  │
│  │ • View logs  │  │ • Debug any  │  │ • No secrets │  │
│  │ • Port-fwd   │  │ • Scale/HPA  │  │ • Audit only │  │
│  │ • Own NS     │  │ • All NS     │  │ • All NS     │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
└─────────────────────────────────────────────────────────┘
```

---

## 2. Developer Role — Namespace-scoped

Developer chỉ có quyền trong namespace được assign, **không thấy cluster resources**.

```yaml
# developer-role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: developer
  labels:
    rbac.platform.io/role: developer
rules:
  # === Workload Management ===
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets", "statefulsets"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
    # Không có "delete" — phải request SRE để xoá
  
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["get", "list", "watch", "delete"]  # delete pod = restart
  
  - apiGroups: [""]
    resources: ["pods/log", "pods/exec", "pods/portforward"]
    verbs: ["get", "create"]
  
  # === Configuration ===
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list"]
    # Không có "create" / "update" — secrets managed by ESO/SealedSecrets
  
  # === Networking ===
  - apiGroups: [""]
    resources: ["services"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  
  # === Batch ===
  - apiGroups: ["batch"]
    resources: ["jobs", "cronjobs"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
  
  # === Events (debug) ===
  - apiGroups: [""]
    resources: ["events"]
    verbs: ["get", "list", "watch"]
  
  # === HPA (view only) ===
  - apiGroups: ["autoscaling"]
    resources: ["horizontalpodautoscalers"]
    verbs: ["get", "list", "watch"]
---
# Binding: developer group → namespace "dev"
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: developer-binding
  namespace: dev                     # Chỉ namespace này
subjects:
  - kind: Group
    name: dev-team
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: developer
  apiGroup: rbac.authorization.k8s.io
```

---

## 3. SRE Role — Cluster-wide

SRE cần quyền **toàn cluster** để debug, scale, và quản lý infrastructure.

```yaml
# sre-clusterrole.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: sre
  labels:
    rbac.platform.io/role: sre
rules:
  # === Mọi namespaced resources ===
  - apiGroups: ["", "apps", "batch", "autoscaling", "networking.k8s.io"]
    resources: ["*"]
    verbs: ["*"]
  
  # === Cluster resources ===
  - apiGroups: [""]
    resources: ["nodes", "persistentvolumes", "namespaces"]
    verbs: ["get", "list", "watch"]
  
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["patch"]                  # Cordon/uncordon
  
  # === RBAC (view only — không tự tạo role) ===
  - apiGroups: ["rbac.authorization.k8s.io"]
    resources: ["roles", "rolebindings", "clusterroles", "clusterrolebindings"]
    verbs: ["get", "list", "watch"]
  
  # === Storage ===
  - apiGroups: ["storage.k8s.io"]
    resources: ["storageclasses", "csinodes"]
    verbs: ["get", "list", "watch"]
  
  # === Monitoring (Prometheus/Grafana CRDs) ===
  - apiGroups: ["monitoring.coreos.com"]
    resources: ["*"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  
  # === Policy (Gatekeeper view) ===
  - apiGroups: ["constraints.gatekeeper.sh", "templates.gatekeeper.sh"]
    resources: ["*"]
    verbs: ["get", "list", "watch"]
  
  # === Argo CD (view) ===
  - apiGroups: ["argoproj.io"]
    resources: ["applications", "appprojects"]
    verbs: ["get", "list", "watch"]
---
# SRE gets cluster-wide access
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: sre-cluster-binding
subjects:
  - kind: Group
    name: sre-team
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: sre
  apiGroup: rbac.authorization.k8s.io
```

---

## 4. Viewer Role — Read-only Cluster-wide

Viewer cho auditor, manager, hoặc cross-team visibility. **Không thấy secrets.**

```yaml
# viewer-clusterrole.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: viewer
  labels:
    rbac.platform.io/role: viewer
rules:
  # === Read-only cho common resources ===
  - apiGroups: ["", "apps", "batch", "autoscaling", "networking.k8s.io"]
    resources: [
      "pods", "services", "deployments", "replicasets",
      "statefulsets", "daemonsets", "jobs", "cronjobs",
      "configmaps", "ingresses", "horizontalpodautoscalers",
      "events", "endpoints", "serviceaccounts",
      "persistentvolumeclaims"
    ]
    verbs: ["get", "list", "watch"]
  
  # === Cluster resources (read-only) ===
  - apiGroups: [""]
    resources: ["nodes", "namespaces", "persistentvolumes"]
    verbs: ["get", "list", "watch"]
  
  # ⚠️ KHÔNG có secrets — viewer không cần thấy credentials
  # ⚠️ KHÔNG có pods/exec — viewer không cần shell access
  # ⚠️ KHÔNG có pods/log — tuỳ org, có thể thêm nếu cần
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: viewer-cluster-binding
subjects:
  - kind: Group
    name: viewers
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: viewer
  apiGroup: rbac.authorization.k8s.io
```

---

## 5. CI/CD ServiceAccount Pattern

CI/CD pipeline (GitHub Actions, GitLab CI) cần ServiceAccount riêng, **KHÔNG dùng user credentials**.

```yaml
# ci-serviceaccount.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: github-actions-deployer
  namespace: cicd
  annotations:
    # IRSA cho EKS
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/github-actions-eks
  labels:
    app.kubernetes.io/managed-by: platform-team
---
# CI/CD chỉ có quyền deploy vào specific namespaces
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ci-deployer
rules:
  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  - apiGroups: [""]
    resources: ["services", "configmaps"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
  # Rollout management
  - apiGroups: ["argoproj.io"]
    resources: ["rollouts"]
    verbs: ["get", "list", "watch", "create", "update", "patch"]
---
# Bind to staging namespace
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ci-deployer-staging
  namespace: staging
subjects:
  - kind: ServiceAccount
    name: github-actions-deployer
    namespace: cicd
roleRef:
  kind: ClusterRole
  name: ci-deployer
  apiGroup: rbac.authorization.k8s.io
---
# Bind to production namespace (separate binding)
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ci-deployer-production
  namespace: production
subjects:
  - kind: ServiceAccount
    name: github-actions-deployer
    namespace: cicd
roleRef:
  kind: ClusterRole
  name: ci-deployer
  apiGroup: rbac.authorization.k8s.io
```

---

## 6. Namespace Isolation Pattern

```yaml
# namespace-with-rbac.yaml
# Tạo namespace + ResourceQuota + RoleBinding trong 1 manifest
apiVersion: v1
kind: Namespace
metadata:
  name: team-alpha
  labels:
    team: alpha
    environment: development
    pod-security.kubernetes.io/enforce: restricted    # Pod Security Standard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: team-alpha-developers
  namespace: team-alpha
subjects:
  - kind: Group
    name: team-alpha
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: developer
  apiGroup: rbac.authorization.k8s.io
---
# Viewer cho cross-team visibility
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: team-alpha-viewers
  namespace: team-alpha
subjects:
  - kind: Group
    name: all-developers       # Tất cả dev xem được NS khác
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: viewer
  apiGroup: rbac.authorization.k8s.io
```

---

## 7. Verify Setup

```bash
# === Verify developer permissions ===
echo "=== Developer in 'dev' namespace ==="
kubectl auth can-i create deployments -n dev \
  --as-group=dev-team --as=developer1
# Expected: yes

kubectl auth can-i delete deployments -n dev \
  --as-group=dev-team --as=developer1
# Expected: no (developer không có delete deployment)

kubectl auth can-i create deployments -n production \
  --as-group=dev-team --as=developer1
# Expected: no (developer chỉ có quyền trong dev)

# === Verify SRE permissions ===
echo "=== SRE cluster-wide ==="
kubectl auth can-i get nodes \
  --as-group=sre-team --as=sre1
# Expected: yes

kubectl auth can-i create clusterroles \
  --as-group=sre-team --as=sre1
# Expected: no (SRE view RBAC only)

# === Verify viewer ===
echo "=== Viewer ==="
kubectl auth can-i get secrets --all-namespaces \
  --as-group=viewers --as=auditor1
# Expected: no

kubectl auth can-i get pods --all-namespaces \
  --as-group=viewers --as=auditor1
# Expected: yes

# === Full permission list ===
kubectl auth can-i --list -n dev --as-group=dev-team --as=dev1
```

---

## 8. RBAC Automation — Scripted Audit

```bash
#!/bin/bash
# rbac-audit.sh — Kiểm tra RBAC configuration

echo "=== ClusterRoleBindings with cluster-admin ==="
kubectl get clusterrolebindings -o json | \
  jq -r '.items[] | select(.roleRef.name == "cluster-admin") | 
         .metadata.name + " → " + 
         (.subjects[]? | .kind + "/" + .name)'

echo ""
echo "=== ServiceAccounts with cluster-admin ==="
kubectl get clusterrolebindings -o json | \
  jq -r '.items[] | select(.roleRef.name == "cluster-admin") |
         .subjects[]? | select(.kind == "ServiceAccount") |
         .namespace + "/" + .name'

echo ""
echo "=== Roles/Bindings per namespace ==="
for ns in $(kubectl get ns -o jsonpath='{.items[*].metadata.name}'); do
  roles=$(kubectl get roles -n $ns --no-headers 2>/dev/null | wc -l)
  bindings=$(kubectl get rolebindings -n $ns --no-headers 2>/dev/null | wc -l)
  if [ "$roles" -gt 0 ] || [ "$bindings" -gt 0 ]; then
    echo "  $ns: $roles roles, $bindings bindings"
  fi
done
```
