# 05 — ValidatingAdmissionPolicy (Native K8s 1.30+)

> **Scope:** CEL-based admission policy, so sánh với Gatekeeper, migration strategy

---

## 1. ValidatingAdmissionPolicy là gì?

**ValidatingAdmissionPolicy (VAP)** = admission policy **native trong K8s** (không cần external webhook). Dùng **CEL (Common Expression Language)** thay vì Rego.

```
                  Before (External Webhook)
┌──────────┐     ┌─────────────────┐     ┌──────────────┐
│ API      │────►│  Webhook call   │────►│  OPA/         │
│ Server   │     │  (HTTPS)        │     │  Gatekeeper   │
└──────────┘     └─────────────────┘     └──────────────┘
     │                                          │
     │◄─────── allow/deny response ────────────┘
     Network hop, latency, single point of failure

                  After (Native K8s 1.30+)
┌──────────────────────────────────────────────┐
│ API Server                                    │
│                                                │
│  ┌──────────────────────────────────────┐     │
│  │  ValidatingAdmissionPolicy          │     │
│  │  (CEL expression evaluated in-proc)  │     │
│  └──────────────────────────────────────┘     │
│                                                │
│  Zero network hop, no webhook dependency       │
└──────────────────────────────────────────────┘
```

### GA Timeline

| K8s Version | Status |
|---|---|
| 1.26 | Alpha |
| 1.28 | Beta |
| 1.30+ | **GA (stable)** |

---

## 2. Thành phần

VAP có **2 resources** (tương tự Gatekeeper's ConstraintTemplate + Constraint):

```
ValidatingAdmissionPolicy    ←→  ConstraintTemplate (define logic)
ValidatingAdmissionPolicyBinding  ←→  Constraint (apply to resources)
```

---

## 3. CEL (Common Expression Language)

CEL = expression language nhẹ, type-safe, **không Turing-complete** (luôn terminate).

### Cú pháp cơ bản

```cel
// Variables có sẵn trong K8s CEL:
// - object: resource đang được tạo/update
// - oldObject: resource trước khi update (chỉ UPDATE)
// - request: admission request metadata
// - params: parameter resource
// - namespaceObject: namespace object
// - authorizer: check authorization

// So sánh
object.spec.replicas <= 100

// String operations
object.metadata.name.startsWith("prod-")
object.metadata.namespace.matches("^team-[a-z]+$")

// Check existence
has(object.metadata.labels) && has(object.metadata.labels.team)

// List operations
object.spec.containers.all(c, has(c.resources) && has(c.resources.limits))
object.spec.containers.exists(c, c.name == "sidecar")
object.spec.containers.filter(c, !has(c.resources.limits)).size() == 0

// Map operations  
object.metadata.labels.all(key, value, key.startsWith("app.kubernetes.io/"))

// Ternary
has(object.metadata.labels.env) ? object.metadata.labels.env : "unknown"

// Type coercion
int(object.metadata.labels["replicas"]) <= 10
```

---

## 4. Ví dụ thực tế

### Ví dụ 1: Require Labels

```yaml
# vap-require-labels.yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: require-team-label
spec:
  failurePolicy: Fail            # Fail | Ignore
  matchConstraints:
    resourceRules:
      - apiGroups: ["apps"]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["deployments", "statefulsets"]
  validations:
    - expression: >-
        has(object.metadata.labels) && 
        has(object.metadata.labels.team) && 
        object.metadata.labels.team.size() > 0
      message: "Deployment/StatefulSet phải có label 'team' (non-empty)"
      reason: Invalid
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: require-team-label-binding
spec:
  policyName: require-team-label
  validationActions:
    - Deny                       # Deny | Warn | Audit
  matchResources:
    namespaceSelector:
      matchExpressions:
        - key: kubernetes.io/metadata.name
          operator: NotIn
          values: ["kube-system", "kube-public", "gatekeeper-system"]
```

### Ví dụ 2: Block Privileged Containers

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: block-privileged
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["pods"]
  validations:
    - expression: >-
        object.spec.containers.all(c, 
          !has(c.securityContext) || 
          !has(c.securityContext.privileged) || 
          c.securityContext.privileged != true
        )
      message: "Containers không được chạy privileged"
    - expression: >-
        !has(object.spec.initContainers) ||
        object.spec.initContainers.all(c,
          !has(c.securityContext) ||
          !has(c.securityContext.privileged) ||
          c.securityContext.privileged != true
        )
      message: "InitContainers không được chạy privileged"
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: block-privileged-binding
spec:
  policyName: block-privileged
  validationActions: [Deny]
  matchResources:
    namespaceSelector:
      matchExpressions:
        - key: kubernetes.io/metadata.name
          operator: NotIn
          values: ["kube-system"]
```

### Ví dụ 3: Require Resource Limits

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: require-resource-limits
spec:
  failurePolicy: Fail
  matchConstraints:
    resourceRules:
      - apiGroups: ["apps"]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["deployments"]
  validations:
    - expression: >-
        object.spec.template.spec.containers.all(c,
          has(c.resources) &&
          has(c.resources.limits) &&
          has(c.resources.limits.cpu) &&
          has(c.resources.limits.memory)
        )
      message: "Mọi container trong Deployment phải có CPU và memory limits"
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: require-resource-limits-binding
spec:
  policyName: require-resource-limits
  validationActions: [Warn]        # Bắt đầu bằng Warn
  matchResources:
    namespaceSelector:
      matchExpressions:
        - key: kubernetes.io/metadata.name
          operator: NotIn
          values: ["kube-system", "monitoring"]
```

### Ví dụ 4: Restrict Replicas

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: max-replicas
spec:
  failurePolicy: Fail
  paramKind:
    apiVersion: v1
    kind: ConfigMap
  matchConstraints:
    resourceRules:
      - apiGroups: ["apps"]
        apiVersions: ["v1"]
        operations: ["CREATE", "UPDATE"]
        resources: ["deployments"]
  validations:
    - expression: >-
        object.spec.replicas <= int(params.data.maxReplicas)
      messageExpression: >-
        "Replicas " + string(object.spec.replicas) + 
        " vượt quá max cho phép: " + params.data.maxReplicas
---
# Parameter ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: replica-limits
  namespace: default
data:
  maxReplicas: "50"
---
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicyBinding
metadata:
  name: max-replicas-binding
spec:
  policyName: max-replicas
  paramRef:
    name: replica-limits
    namespace: default
    parameterNotFoundAction: Deny
  validationActions: [Deny]
```

---

## 5. Validation Actions

| Action | Hành vi | Tương đương Gatekeeper |
|---|---|---|
| `Deny` | Chặn request, trả error | `enforcementAction: deny` |
| `Warn` | Cho phép, trả warning header | `enforcementAction: warn` |
| `Audit` | Cho phép, ghi vào audit log | `enforcementAction: dryrun` |

```yaml
# Có thể combine nhiều actions
validationActions:
  - Warn    # User thấy warning
  - Audit   # Ghi audit log
# → Cho phép resource nhưng vừa warn vừa audit
```

---

## 6. So sánh Gatekeeper vs ValidatingAdmissionPolicy

| Feature | Gatekeeper | ValidatingAdmissionPolicy |
|---|---|---|
| **Language** | Rego (powerful, flexible) | CEL (simpler, limited) |
| **Install** | Helm chart, webhook | Built-in K8s 1.30+ |
| **Dependencies** | External pods | None |
| **Latency** | Network hop to webhook | In-process |
| **Failure mode** | Webhook down = ??? | No external dependency |
| **Audit existing** | ✅ Native audit scan | ✅ Audit action |
| **Mutation** | ✅ (Assign, AssignMetadata) | ❌ (chỉ validation) |
| **External data** | ✅ (sync resources) | ⚠️ Limited (params only) |
| **Complex logic** | ✅ Full Rego | ⚠️ CEL limitations |
| **Ecosystem** | Mature, large library | New, growing |
| **Parameterized** | ✅ Constraint params | ✅ ConfigMap/CRD params |

### Khi nào dùng gì?

```
Use Gatekeeper when:
├── Cần mutation (inject sidecar, add labels)
├── Logic phức tạp (cross-resource validation)
├── Cần external data (check resource từ namespace khác)
├── Team đã quen Rego
└── Cần policy library lớn

Use ValidatingAdmissionPolicy when:
├── K8s 1.30+ available
├── Policy đơn giản (label check, resource limits)
├── Muốn giảm dependency
├── Performance critical (no webhook latency)
└── Bắt đầu mới, chưa có Gatekeeper
```

---

## 7. Migration: Gatekeeper → VAP

### Step 1: Identify simple policies for migration

```bash
# Policies phù hợp migrate sang VAP:
# - require-labels
# - require-resource-limits
# - block-privileged
# - max-replicas

# Policies NÊN giữ Gatekeeper:
# - allowed-repos (complex string matching)
# - cross-resource validation
# - mutation policies
```

### Step 2: Dual-run (cả hai cùng chạy)

```yaml
# Gatekeeper constraint: chuyển sang dryrun
spec:
  enforcementAction: dryrun    # Không block nữa

# VAP binding: enforce
validationActions: [Deny]       # VAP enforce thay
```

### Step 3: Verify + Remove Gatekeeper constraint

```bash
# So sánh violations count
kubectl get constraints -o wide
# vs
kubectl get validatingadmissionpolicybinding
```

---

## 8. CEL Cheat Sheet

```cel
// === String ===
s.startsWith("prefix")
s.endsWith("suffix")
s.contains("sub")
s.matches("regex")
s.size()                        // length
s.lowerAscii()
s.upperAscii()
s.trim()
s.replace("old", "new")
s.split(".")

// === List ===
list.all(x, expr)              // Tất cả phải đúng
list.exists(x, expr)           // Ít nhất 1 đúng
list.exists_one(x, expr)       // Đúng 1
list.filter(x, expr)           // Lọc
list.map(x, expr)              // Transform
list.size()                     // Length

// === Map ===
has(map.key)                   // Key exists?
map.all(k, v, expr)            // All entries match?

// === Type check ===
type(object) == string
type(object) == int

// === URL (K8s extension) ===
url("https://example.com").getScheme()    // "https"
url("https://example.com").getHost()      // "example.com"

// === Quantity (K8s extension) ===
quantity("1.5Gi").isGreaterThan(quantity("1Gi"))   // true
quantity("500m").isLessThan(quantity("1"))          // true (CPU)
```
