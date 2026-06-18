# 01 — RBAC Fundamentals

> **Scope:** Role, ClusterRole, RoleBinding, ClusterRoleBinding, ServiceAccount, `kubectl auth can-i`

---

## 1. RBAC là gì?

**RBAC (Role-Based Access Control)** = cơ chế authorization mặc định của Kubernetes. Nó trả lời câu hỏi: **"Subject X có được phép Verb Y trên Resource Z trong namespace N không?"**

```
RBAC = WHO (Subject) + WHAT (Verb) + WHERE (Resource + Namespace)
```

### Bật RBAC

RBAC được bật mặc định từ K8s 1.6+. Kiểm tra:

```bash
# Kiểm tra API server có flag --authorization-mode=RBAC
kubectl api-versions | grep rbac
# Output: rbac.authorization.k8s.io/v1

# Hoặc kiểm tra trực tiếp
kubectl cluster-info dump | grep authorization-mode
```

---

## 2. Bốn loại RBAC Resources

### 2.1 Role (namespace-scoped)

Định nghĩa **tập hợp permissions** trong **một namespace cụ thể**.

```yaml
# role-pod-reader.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: development
  name: pod-reader
rules:
  # Rule 1: Đọc pods
  - apiGroups: [""]            # "" = core API group
    resources: ["pods"]
    verbs: ["get", "list", "watch"]
  
  # Rule 2: Đọc pod logs
  - apiGroups: [""]
    resources: ["pods/log"]
    verbs: ["get"]
  
  # Rule 3: Đọc configmaps
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "list"]
```

### 2.2 ClusterRole (cluster-scoped)

Giống Role nhưng **áp dụng toàn cluster** hoặc cho **non-namespaced resources** (nodes, PV, namespaces...).

```yaml
# clusterrole-node-viewer.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: node-viewer     # Không có namespace field!
rules:
  # Cluster-wide resources (không có namespace)
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["get", "list", "watch"]
  
  - apiGroups: [""]
    resources: ["persistentvolumes"]
    verbs: ["get", "list"]
  
  # Namespaced resources — khi bind bằng ClusterRoleBinding
  # sẽ áp dụng cho TẤT CẢ namespaces
  - apiGroups: [""]
    resources: ["pods", "services"]
    verbs: ["get", "list", "watch"]
```

### 2.3 RoleBinding (namespace-scoped)

**Gắn Role/ClusterRole** vào **Subject** trong **một namespace**.

```yaml
# rolebinding-dev-pod-reader.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: dev-pod-reader
  namespace: development       # Chỉ có hiệu lực trong namespace này
subjects:
  # Subject 1: User
  - kind: User
    name: alice@company.com
    apiGroup: rbac.authorization.k8s.io
  
  # Subject 2: Group (từ OIDC / Certificate)
  - kind: Group
    name: dev-team
    apiGroup: rbac.authorization.k8s.io
  
  # Subject 3: ServiceAccount
  - kind: ServiceAccount
    name: ci-deployer
    namespace: development     # Namespace của ServiceAccount
roleRef:
  kind: Role                   # Hoặc ClusterRole
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

> **Trick quan trọng:** RoleBinding có thể reference **ClusterRole** nhưng scope chỉ trong namespace của RoleBinding. Dùng pattern này để tái sử dụng ClusterRole nhưng giới hạn scope.

### 2.4 ClusterRoleBinding (cluster-scoped)

**Gắn ClusterRole** vào Subject **toàn cluster**.

```yaml
# clusterrolebinding-sre-admin.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: sre-cluster-admin
subjects:
  - kind: Group
    name: sre-team
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin          # Built-in ClusterRole
  apiGroup: rbac.authorization.k8s.io
```

---

## 3. Matrix: Scope kết hợp

```
                    │ RoleBinding           │ ClusterRoleBinding
                    │ (namespace-scoped)    │ (cluster-scoped)
────────────────────┼───────────────────────┼──────────────────────
Role                │ ✅ Quyền trong NS     │ ❌ Không hợp lệ
(namespace-scoped)  │    đó                │
────────────────────┼───────────────────────┼──────────────────────
ClusterRole         │ ✅ Quyền trong NS     │ ✅ Quyền toàn cluster
(cluster-scoped)    │    đó (reuse role)   │    (mọi namespace)
```

---

## 4. ServiceAccount

**ServiceAccount** = identity cho **workload chạy trong pod**, KHÔNG phải user.

```yaml
# serviceaccount-ci.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ci-deployer
  namespace: development
  annotations:
    # EKS: IRSA — gắn IAM Role cho ServiceAccount
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/ci-deployer-role
---
# Secret auto-mount bị disable mặc định từ K8s 1.24+
# Phải tạo Secret riêng nếu cần token
apiVersion: v1
kind: Secret
metadata:
  name: ci-deployer-token
  namespace: development
  annotations:
    kubernetes.io/service-account.name: ci-deployer
type: kubernetes.io/service-account-token
```

### Gắn ServiceAccount vào Pod

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: ci-runner
  namespace: development
spec:
  serviceAccountName: ci-deployer    # Pod chạy với identity này
  automountServiceAccountToken: true  # Mount token vào pod
  containers:
    - name: runner
      image: bitnami/kubectl:latest
```

### Default ServiceAccount

Mỗi namespace tự động có `default` ServiceAccount. **KHÔNG nên dùng** cho production — tạo SA riêng cho từng workload.

```bash
# Xem ServiceAccounts trong namespace
kubectl get sa -n development

# Output:
# NAME          SECRETS   AGE
# default       0         10d
# ci-deployer   0         2d
```

---

## 5. Verbs — Hành động trong RBAC

| Verb | Mô tả | HTTP Method |
|---|---|---|
| `get` | Đọc 1 resource cụ thể | GET (single) |
| `list` | Liệt kê resources | GET (collection) |
| `watch` | Stream changes (real-time) | GET (watch) |
| `create` | Tạo mới | POST |
| `update` | Cập nhật toàn bộ | PUT |
| `patch` | Cập nhật một phần | PATCH |
| `delete` | Xoá 1 resource | DELETE |
| `deletecollection` | Xoá nhiều resources | DELETE (collection) |
| `impersonate` | Giả mạo identity | — |
| `bind` | Tạo binding | — |
| `escalate` | Tạo role có quyền cao hơn mình | — |

> **Chú ý:** `*` = tất cả verbs. **Rất nguy hiểm** — chỉ dùng cho cluster-admin.

---

## 6. `kubectl auth can-i` — Kiểm tra quyền

```bash
# === Kiểm tra quyền của chính mình ===

# Có thể tạo deployment trong namespace "dev" không?
kubectl auth can-i create deployments -n dev
# Output: yes / no

# Có thể xoá pods trong mọi namespace không?
kubectl auth can-i delete pods --all-namespaces
# Output: no

# Liệt kê TẤT CẢ quyền của mình trong namespace "dev"
kubectl auth can-i --list -n dev

# === Kiểm tra quyền của user/SA khác (cần impersonate) ===

# Alice có thể tạo pod trong namespace "production" không?
kubectl auth can-i create pods -n production \
  --as=alice@company.com

# ServiceAccount ci-deployer có thể update deployments không?
kubectl auth can-i update deployments -n dev \
  --as=system:serviceaccount:dev:ci-deployer

# Group dev-team có thể xoá services không?
kubectl auth can-i delete services -n dev \
  --as-group=dev-team

# === Trong CI/CD pipeline — pre-check trước khi deploy ===
kubectl auth can-i create deployments -n production \
  --as=system:serviceaccount:cicd:github-actions \
  && echo "✅ SA has deploy permission" \
  || echo "❌ Missing permission — check RBAC"
```

---

## 7. Built-in ClusterRoles

K8s có sẵn 4 ClusterRoles quan trọng:

| ClusterRole | Quyền | Use case |
|---|---|---|
| `cluster-admin` | **Mọi thứ** (God mode) | Platform admin, emergency only |
| `admin` | Quản lý resources trong namespace (trừ ResourceQuota, namespace) | Team lead, namespace owner |
| `edit` | Tạo/sửa/xoá workloads (trừ roles/bindings) | Developer |
| `view` | Chỉ đọc (get/list/watch), không thấy secrets | Viewer, auditor |

```bash
# Xem chi tiết built-in role
kubectl describe clusterrole admin

# Xem tất cả ClusterRoles
kubectl get clusterroles | grep -v "system:"
```

---

## 8. Aggregated ClusterRoles

**Aggregated ClusterRoles** = tự động merge rules từ nhiều ClusterRoles dựa trên label selectors. Built-in roles (`admin`, `edit`, `view`) dùng cơ chế này.

```yaml
# Tạo custom ClusterRole tự động merge vào "admin"
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: custom-crd-admin
  labels:
    # Label này khiến rules được merge vào ClusterRole "admin"
    rbac.authorization.k8s.io/aggregate-to-admin: "true"
rules:
  - apiGroups: ["mycompany.io"]
    resources: ["myresources"]
    verbs: ["get", "list", "watch", "create", "update", "delete"]
```

---

## 9. Common Pitfalls

### ❌ Sai: Dùng ClusterRoleBinding cho namespaced permissions

```yaml
# NGUY HIỂM: Cho developer quyền edit TOÀN BỘ cluster
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding      # ← Sai! Dùng RoleBinding
metadata:
  name: dev-edit
subjects:
  - kind: User
    name: alice@company.com
roleRef:
  kind: ClusterRole
  name: edit                   # Giờ Alice edit được MỌI namespace
```

### ✅ Đúng: Dùng RoleBinding + ClusterRole

```yaml
# Chỉ cho Alice edit trong namespace "development"
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding              # ← Đúng! Scope namespace
metadata:
  name: dev-edit
  namespace: development       # Chỉ namespace này
subjects:
  - kind: User
    name: alice@company.com
roleRef:
  kind: ClusterRole            # Reuse ClusterRole "edit"
  name: edit
```

### ❌ Sai: Wildcard resources

```yaml
rules:
  - apiGroups: ["*"]
    resources: ["*"]
    verbs: ["*"]
# → Equivalent cluster-admin. TUYỆT ĐỐI không dùng trừ emergency.
```

---

## 10. Debug RBAC Issues

```bash
# Khi gặp "Error from server (Forbidden)":

# 1. Check quyền hiện tại
kubectl auth can-i --list -n <namespace>

# 2. Check SA của pod
kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.serviceAccountName}'

# 3. Check bindings
kubectl get rolebindings -n <ns>
kubectl get clusterrolebindings | grep <subject>

# 4. Check role details
kubectl describe role <role> -n <ns>
kubectl describe clusterrole <role>

# 5. Audit log (EKS CloudWatch)
# Tìm decision: "Forbidden" trong audit log
```
