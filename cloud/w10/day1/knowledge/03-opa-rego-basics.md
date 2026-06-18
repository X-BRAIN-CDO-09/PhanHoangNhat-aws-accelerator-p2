# 03 — OPA & Rego Basics

> **Scope:** OPA architecture, Rego language fundamentals, playground, policy testing

---

## 1. OPA là gì?

**OPA (Open Policy Agent)** = general-purpose policy engine. Nó KHÔNG phải riêng của K8s — dùng cho bất kỳ system nào cần policy decision.

```
┌──────────────────────────────────────────────────┐
│                   OPA Engine                      │
│                                                    │
│  Input (JSON)  ──►  Rego Policy  ──►  Decision    │
│                                       (JSON)      │
│                                                    │
│  Ví dụ:                                           │
│  • K8s: AdmissionReview → allow/deny              │
│  • API Gateway: Request → authorize/reject         │
│  • Terraform: Plan → compliant/violating           │
│  • CI/CD: Config → approve/block                   │
└──────────────────────────────────────────────────┘
```

### OPA trong K8s ecosystem

```
                              ┌─────────────┐
                              │  Gatekeeper  │  ← OPA wrapper cho K8s
                              │  (K8s-native)│
                              └──────┬───────┘
                                     │ uses
                              ┌──────▼───────┐
kubectl apply ──► API Server ─►│    OPA       │──► allow / deny
                              │  (Rego eval) │
                              └──────────────┘
```

---

## 2. Rego Language — Cú pháp cơ bản

Rego là **declarative policy language** — bạn mô tả **"cái gì phải đúng"** thay vì **"làm sao check"**.

### 2.1 Package và Rule

```rego
# Package = namespace cho policies
package kubernetes.admission

# Default value
default allow := false

# Rule: allow = true NẾU tất cả conditions đều đúng
allow if {
    input.request.kind.kind == "Pod"
    input.request.object.metadata.labels.team
    not is_privileged
}

# Helper rule
is_privileged if {
    input.request.object.spec.containers[_].securityContext.privileged == true
}
```

### 2.2 Input — Data đầu vào

Trong K8s context, `input` là **AdmissionReview** object:

```json
{
  "request": {
    "uid": "abc-123",
    "kind": {"kind": "Pod", "group": "", "version": "v1"},
    "operation": "CREATE",
    "userInfo": {
      "username": "alice@company.com",
      "groups": ["dev-team", "system:authenticated"]
    },
    "object": {
      "metadata": {
        "name": "my-pod",
        "namespace": "dev",
        "labels": {
          "team": "alpha",
          "app": "my-app"
        }
      },
      "spec": {
        "containers": [{
          "name": "app",
          "image": "myrepo/app:v1.2",
          "securityContext": {
            "privileged": false,
            "runAsNonRoot": true
          }
        }]
      }
    }
  }
}
```

### 2.3 Iteration — Duyệt collection

```rego
# "_" = iterate qua mọi element
# Check TẤT CẢ containers có resource limits
violation[{"msg": msg}] if {
    container := input.request.object.spec.containers[_]
    not container.resources.limits.cpu
    msg := sprintf("Container '%v' thiếu CPU limit", [container.name])
}

# Check TẤT CẢ containers có image từ trusted registry
violation[{"msg": msg}] if {
    container := input.request.object.spec.containers[_]
    not startswith(container.image, "123456789012.dkr.ecr.")
    not startswith(container.image, "ghcr.io/myorg/")
    msg := sprintf("Container '%v' dùng untrusted image: %v", 
                   [container.name, container.image])
}
```

### 2.4 Built-in Functions

```rego
# String functions
startswith("hello", "hel")              # true
endswith("hello.yaml", ".yaml")          # true
contains("hello world", "world")         # true
sprintf("User %v in NS %v", ["alice", "dev"])  # "User alice in NS dev"
regex.match("^v[0-9]+", "v1.2.3")       # true

# Collection functions
count(input.request.object.spec.containers)   # Số containers
array.concat([1, 2], [3, 4])                  # [1, 2, 3, 4]

# Type checking
is_string("hello")    # true
is_number(42)          # true
is_boolean(true)       # true
is_null(null)          # true
is_object({"a": 1})    # true
is_array([1, 2])       # true

# Time
time.now_ns()          # Current time in nanoseconds
time.parse_rfc3339_ns("2024-01-01T00:00:00Z")
```

### 2.5 Comprehensions

```rego
# Set comprehension — tập hợp unique values
privileged_containers := {name |
    container := input.request.object.spec.containers[_]
    container.securityContext.privileged == true
    name := container.name
}

# Array comprehension
container_names := [name |
    container := input.request.object.spec.containers[_]
    name := container.name
]

# Object comprehension
container_images := {name: image |
    container := input.request.object.spec.containers[_]
    name := container.name
    image := container.image
}
```

---

## 3. Rego Patterns cho K8s

### Pattern 1: Require Labels

```rego
package k8srequiredlabels

violation[{"msg": msg}] if {
    # Lấy labels từ object
    provided := {label | input.review.object.metadata.labels[label]}
    
    # Required labels từ constraint parameter
    required := {label | label := input.parameters.labels[_]}
    
    # Tìm labels thiếu
    missing := required - provided
    count(missing) > 0
    
    msg := sprintf("Object thiếu required labels: %v", [missing])
}
```

### Pattern 2: Block Privileged Containers

```rego
package k8sblockprivileged

violation[{"msg": msg}] if {
    container := input.review.object.spec.containers[_]
    container.securityContext.privileged == true
    msg := sprintf("Container '%v' không được chạy privileged", [container.name])
}

# Cũng check initContainers
violation[{"msg": msg}] if {
    container := input.review.object.spec.initContainers[_]
    container.securityContext.privileged == true
    msg := sprintf("InitContainer '%v' không được chạy privileged", [container.name])
}
```

### Pattern 3: Allowed Registries

```rego
package k8sallowedrepos

violation[{"msg": msg}] if {
    container := input.review.object.spec.containers[_]
    
    # Check image không match bất kỳ allowed repo nào
    not image_matches_any(container.image)
    
    msg := sprintf(
        "Container '%v' dùng image '%v' — chỉ được dùng từ: %v",
        [container.name, container.image, input.parameters.repos]
    )
}

image_matches_any(image) if {
    repo := input.parameters.repos[_]
    startswith(image, repo)
}
```

---

## 4. Testing Rego Policies

### Unit Test

```rego
# policy_test.rego
package k8srequiredlabels

# Test case: object có đủ labels → không violation
test_allow_with_all_labels if {
    count(violation) == 0 with input as {
        "review": {
            "object": {
                "metadata": {
                    "labels": {
                        "team": "alpha",
                        "env": "production"
                    }
                }
            }
        },
        "parameters": {
            "labels": ["team", "env"]
        }
    }
}

# Test case: thiếu label → có violation
test_deny_missing_label if {
    count(violation) > 0 with input as {
        "review": {
            "object": {
                "metadata": {
                    "labels": {
                        "team": "alpha"
                        # Thiếu "env"
                    }
                }
            }
        },
        "parameters": {
            "labels": ["team", "env"]
        }
    }
}

# Test case: không có labels gì → violation
test_deny_no_labels if {
    count(violation) > 0 with input as {
        "review": {
            "object": {
                "metadata": {
                    "labels": {}
                }
            }
        },
        "parameters": {
            "labels": ["team"]
        }
    }
}
```

### Chạy test

```bash
# Cài OPA CLI
brew install opa    # macOS
# hoặc download binary từ https://www.openpolicyagent.org/docs/latest/#running-opa

# Chạy test
opa test . -v
# Output:
# data.k8srequiredlabels.test_allow_with_all_labels: PASS (1.234ms)
# data.k8srequiredlabels.test_deny_missing_label: PASS (0.567ms)
# data.k8srequiredlabels.test_deny_no_labels: PASS (0.432ms)

# Chạy test với coverage
opa test . -v --coverage
```

---

## 5. OPA Playground

Dùng **https://play.openpolicyagent.org** để test Rego interactively:

1. Paste policy vào editor
2. Paste input JSON
3. Click "Evaluate"
4. Xem output

> **Tip:** Luôn test policy trên Playground trước khi deploy vào cluster.

---

## 6. Rego Style Guide

| Rule | Giải thích |
|---|---|
| Đặt tên package theo domain | `kubernetes.admission`, `ci.image_policy` |
| Dùng `violation` cho deny rules | Gatekeeper convention |
| Include `msg` trong violation | Giúp debug khi bị deny |
| Test mọi rule | `_test.rego` file cùng thư mục |
| Tránh `not` phức tạp | Khó đọc, dễ sai logic |
| Dùng helper rules | Tách logic phức tạp |
| Comment giải thích WHY | Không chỉ WHAT |
