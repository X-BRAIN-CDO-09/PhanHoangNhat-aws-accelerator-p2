# 04 — Gatekeeper (OPA for Kubernetes)

> **Scope:** Gatekeeper install, ConstraintTemplate vs Constraint, audit vs enforce, policy library

---

## 1. Gatekeeper là gì?

**Gatekeeper** = OPA wrapper chuyên cho Kubernetes. Nó biến OPA policies thành **K8s-native CRDs** — quản lý bằng `kubectl`, GitOps, Terraform.

```
                    Gatekeeper Components
┌──────────────────────────────────────────────────────┐
│                                                        │
│  ConstraintTemplate (CRD)     Constraint (CRD)        │
│  ┌────────────────────┐       ┌──────────────────┐    │
│  │ • Rego policy code │       │ • Parameters     │    │
│  │ • Parameter schema │ ◄──── │ • Match criteria │    │
│  │ • Target template  │       │ • Enforcement    │    │
│  └────────────────────┘       └──────────────────┘    │
│           │                           │                │
│           └───────────┬───────────────┘                │
│                       ▼                                │
│              Gatekeeper Controller                     │
│              (ValidatingWebhook)                       │
│                       │                                │
│                       ▼                                │
│              K8s API Server                            │
│              (admit / reject request)                  │
└──────────────────────────────────────────────────────┘
```

### Tại sao Gatekeeper thay vì raw OPA?

| Feature | Raw OPA | Gatekeeper |
|---|---|---|
| K8s native CRDs | ❌ | ✅ ConstraintTemplate + Constraint |
| Audit existing resources | ❌ | ✅ `audit` mode |
| Parameter reuse | Manual | ✅ Schema + Constraint params |
| Status/violations | Manual | ✅ `.status.violations` |
| GitOps friendly | Cần custom | ✅ Native YAML |
| Policy library | Write from scratch | ✅ gatekeeper-library |

---

## 2. Installation

```bash
# Cài Gatekeeper bằng Helm
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm repo update

helm install gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system \
  --create-namespace \
  --set replicas=3 \
  --set audit.replicas=1 \
  --set audit.interval=60 \
  --set constraintViolationsLimit=100

# Verify
kubectl get pods -n gatekeeper-system
# NAME                                          READY   STATUS
# gatekeeper-audit-xxx                          1/1     Running
# gatekeeper-controller-manager-xxx             1/1     Running
# gatekeeper-controller-manager-xxx             1/1     Running
# gatekeeper-controller-manager-xxx             1/1     Running

# Check CRDs
kubectl get crd | grep gatekeeper
# configs.config.gatekeeper.sh
# constraintpodstatuses.status.gatekeeper.sh
# constrainttemplatepodstatuses.status.gatekeeper.sh
# constrainttemplates.templates.gatekeeper.sh
# ...
```

---

## 3. ConstraintTemplate — Định nghĩa Policy

ConstraintTemplate = **"loại policy"** — chứa Rego code + parameter schema.

### Ví dụ 1: Require Labels

```yaml
# constraint-templates/require-labels.yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiredlabels
  annotations:
    description: "Requires specified labels on resources"
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredLabels            # Tên CRD mới được tạo
      validation:
        openAPIV3Schema:
          type: object
          properties:
            labels:
              type: array
              description: "List of required label keys"
              items:
                type: string
            message:
              type: string
              description: "Custom error message"
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequiredlabels

        violation[{"msg": msg}] {
          provided := {label | input.review.object.metadata.labels[label]}
          required := {label | label := input.parameters.labels[_]}
          missing := required - provided
          count(missing) > 0
          
          def_msg := sprintf("Resource '%v/%v' thiếu required labels: %v", [
            input.review.object.kind,
            input.review.object.metadata.name,
            missing
          ])
          msg := object.get(input.parameters, "message", def_msg)
        }
```

### Ví dụ 2: Block Privileged Containers

```yaml
# constraint-templates/block-privileged.yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8sblockprivileged
  annotations:
    description: "Blocks privileged containers"
spec:
  crd:
    spec:
      names:
        kind: K8sBlockPrivileged
      validation:
        openAPIV3Schema:
          type: object
          properties:
            exemptImages:
              type: array
              description: "Images exempt from this policy"
              items:
                type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8sblockprivileged

        violation[{"msg": msg}] {
          container := input.review.object.spec.containers[_]
          container.securityContext.privileged == true
          not is_exempt(container.image)
          msg := sprintf("Container '%v' trong %v '%v' không được chạy privileged", [
            container.name,
            input.review.object.kind,
            input.review.object.metadata.name
          ])
        }

        violation[{"msg": msg}] {
          container := input.review.object.spec.initContainers[_]
          container.securityContext.privileged == true
          not is_exempt(container.image)
          msg := sprintf("InitContainer '%v' không được chạy privileged", [container.name])
        }

        is_exempt(image) {
          exempt := input.parameters.exemptImages[_]
          startswith(image, exempt)
        }
```

### Ví dụ 3: Require Resource Limits

```yaml
# constraint-templates/require-limits.yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequireresourcelimits
spec:
  crd:
    spec:
      names:
        kind: K8sRequireResourceLimits
      validation:
        openAPIV3Schema:
          type: object
          properties:
            requiredLimits:
              type: array
              items:
                type: string
                enum: ["cpu", "memory"]
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequireresourcelimits

        violation[{"msg": msg}] {
          container := input.review.object.spec.containers[_]
          required := input.parameters.requiredLimits[_]
          not container.resources.limits[required]
          msg := sprintf("Container '%v' thiếu resource limit: %v", [
            container.name, required
          ])
        }
```

### Ví dụ 4: Allowed Repositories

```yaml
# constraint-templates/allowed-repos.yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8sallowedrepos
spec:
  crd:
    spec:
      names:
        kind: K8sAllowedRepos
      validation:
        openAPIV3Schema:
          type: object
          properties:
            repos:
              type: array
              items:
                type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8sallowedrepos

        violation[{"msg": msg}] {
          container := input.review.object.spec.containers[_]
          not image_allowed(container.image)
          msg := sprintf("Container '%v' dùng image '%v' — chỉ cho phép: %v", [
            container.name, container.image, input.parameters.repos
          ])
        }

        image_allowed(image) {
          repo := input.parameters.repos[_]
          startswith(image, repo)
        }
```

---

## 4. Constraint — Áp dụng Policy

Constraint = **instance** của ConstraintTemplate với **parameters cụ thể** và **match criteria**.

```yaml
# constraints/require-team-label.yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels                     # Tên CRD từ ConstraintTemplate
metadata:
  name: require-team-label
spec:
  enforcementAction: deny                    # deny | dryrun | warn
  match:
    kinds:
      - apiGroups: ["apps"]
        kinds: ["Deployment", "StatefulSet"]
      - apiGroups: [""]
        kinds: ["Pod"]
    excludedNamespaces:                      # Exclude system namespaces
      - kube-system
      - kube-public
      - gatekeeper-system
  parameters:
    labels: ["team"]
    message: "Mọi Deployment/StatefulSet/Pod phải có label 'team'"
---
# constraints/block-privileged-pods.yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sBlockPrivileged
metadata:
  name: block-privileged-pods
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
      - apiGroups: ["apps"]
        kinds: ["Deployment", "StatefulSet", "DaemonSet"]
    excludedNamespaces:
      - kube-system
      - gatekeeper-system
      - monitoring           # Prometheus cần privileged cho node-exporter
  parameters:
    exemptImages:
      - "quay.io/prometheus/node-exporter"    # Exception có lý do
---
# constraints/require-limits.yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequireResourceLimits
metadata:
  name: require-cpu-memory-limits
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: ["apps"]
        kinds: ["Deployment", "StatefulSet"]
    excludedNamespaces:
      - kube-system
      - gatekeeper-system
  parameters:
    requiredLimits: ["cpu", "memory"]
---
# constraints/allowed-registries.yaml
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sAllowedRepos
metadata:
  name: allowed-registries
spec:
  enforcementAction: warn                    # Bắt đầu bằng warn
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
      - apiGroups: ["apps"]
        kinds: ["Deployment", "StatefulSet", "DaemonSet"]
    excludedNamespaces:
      - kube-system
      - gatekeeper-system
  parameters:
    repos:
      - "123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/"
      - "ghcr.io/myorg/"
      - "docker.io/library/"               # Official images
```

---

## 5. Enforcement Actions

| Action | Hành vi | Khi nào dùng |
|---|---|---|
| `deny` | **Chặn** request, trả error | Production enforce |
| `warn` | Cho phép nhưng **log warning** vào admission response | Giai đoạn rollout |
| `dryrun` | Cho phép, chỉ **ghi audit log** | Initial discovery |

### Audit Mode — Kiểm tra violations trên existing resources

```bash
# Xem violations hiện tại (audit scan)
kubectl get k8srequiredlabels require-team-label -o yaml

# Output:
# status:
#   auditTimestamp: "2024-01-15T10:30:00Z"
#   totalViolations: 12
#   violations:
#     - enforcementAction: deny
#       kind: Deployment
#       name: legacy-app
#       namespace: production
#       message: "Mọi Deployment phải có label 'team'"
#     - ...

# Shortcut: xem violations count
kubectl get constraints
# NAME                        ENFORCEMENT-ACTION   TOTAL-VIOLATIONS
# require-team-label          deny                 12
# block-privileged-pods       deny                 3
# require-cpu-memory-limits   deny                 25
# allowed-registries          warn                 8
```

---

## 6. Gatekeeper Config — Sync Resources for Audit

Gatekeeper cần biết resources nào để audit (ngoài admission requests):

```yaml
# gatekeeper-config.yaml
apiVersion: config.gatekeeper.sh/v1alpha1
kind: Config
metadata:
  name: config
  namespace: gatekeeper-system
spec:
  sync:
    syncOnly:
      - group: ""
        version: "v1"
        kind: "Namespace"
      - group: ""
        version: "v1"
        kind: "Pod"
      - group: "apps"
        version: "v1"
        kind: "Deployment"
      - group: "networking.k8s.io"
        version: "v1"
        kind: "Ingress"
  match:
    - excludedNamespaces:
        - kube-system
      processes:
        - "audit"
        - "webhook"
```

---

## 7. Gatekeeper Policy Library

**https://open-policy-agent.github.io/gatekeeper-library/website/**

Thay vì viết Rego từ đầu, dùng library có sẵn:

| Policy | Mô tả |
|---|---|
| `K8sRequiredLabels` | Yêu cầu labels |
| `K8sBlockPrivilegedContainer` | Chặn privileged |
| `K8sContainerLimits` | Yêu cầu resource limits |
| `K8sAllowedRepos` | Whitelist image registries |
| `K8sBlockNodePort` | Chặn NodePort services |
| `K8sHttpsOnly` | Yêu cầu HTTPS cho Ingress |
| `K8sDisallowedTags` | Chặn `latest` tag |
| `K8sRequiredProbes` | Yêu cầu liveness/readiness |
| `K8sPSPCapabilities` | Restrict Linux capabilities |

```bash
# Install từ library
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper-library/master/library/general/requiredlabels/template.yaml
```

---

## 8. Troubleshooting Gatekeeper

```bash
# Logs
kubectl logs -n gatekeeper-system deployment/gatekeeper-controller-manager -f
kubectl logs -n gatekeeper-system deployment/gatekeeper-audit -f

# Webhook status
kubectl get validatingwebhookconfigurations gatekeeper-validating-webhook-configuration

# ConstraintTemplate status
kubectl get constrainttemplates
kubectl describe constrainttemplate k8srequiredlabels

# Constraint violations
kubectl get constraints -o wide

# Test: thử deploy resource vi phạm
kubectl run test-privileged \
  --image=nginx \
  --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"test","image":"nginx","securityContext":{"privileged":true}}]}}' \
  -n dev

# Expected: Error from server (Forbidden): admission webhook "validation.gatekeeper.sh" denied the request
```
