# W9 — D1: GitOps & CI/CD

> **Ngày:** T2 08/06/2026 | **Theme:** Deliver Smartly
> **Commit prefix:** `[W9-D1]`

---

## 🎯 Mục tiêu học tập

Sau ngày hôm nay, bạn có thể:

- [ ] Giải thích GitOps là gì và tại sao dùng nó thay vì `kubectl apply` thủ công
- [ ] Phân biệt ArgoCD vs Flux (push vs pull model)
- [ ] Hiểu App-of-Apps pattern và sync waves
- [ ] Cấu hình GitHub Actions: plan-on-PR, apply-on-merge
- [ ] Thực hiện rollback đúng cách: `git revert` vs `kubectl rollout undo`

---

## 📚 Kiến thức trọng tâm

### 1. GitOps — Nền tảng tư duy

**GitOps = Git là source of truth duy nhất cho infrastructure và application state.**

#### 4 nguyên tắc cốt lõi (OpenGitOps)

| Nguyên tắc | Giải thích | Ví dụ thực tế |
|---|---|---|
| **Declarative** | Mô tả trạng thái mong muốn, không phải cách đạt đến | YAML manifest, không phải shell script |
| **Versioned & Immutable** | Git là nguồn sự thật duy nhất, có lịch sử rõ ràng | `git log` thấy ai thay đổi gì, khi nào |
| **Pulled Automatically** | Agent trong cluster tự pull state mới, không bị push từ ngoài | ArgoCD/Flux tự sync, không cần CI push vào cluster |
| **Continuously Reconciled** | Agent liên tục so sánh desired state vs actual state và tự sửa | Drift detection + auto-heal |

> **Tại sao quan trọng?** Không còn ai có quyền `kubectl apply` trực tiếp vào production — mọi thay đổi đều phải qua Git → audit trail đầy đủ.

---

### 2. ArgoCD vs Flux — So sánh chi tiết

#### Mô hình hoạt động

```
┌─────────────────────────────────────────────────────┐
│  PUSH model (truyền thống — KHÔNG GitOps thuần)     │
│  CI/CD pipeline → kubectl apply → Cluster           │
│  ❌ Cluster expose API ra ngoài, không audit trail   │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│  PULL model (GitOps — ArgoCD / Flux)                │
│  Git repo ← ArgoCD/Flux agent (trong cluster) pull  │
│  ✅ Cluster không expose, tự reconcile               │
└─────────────────────────────────────────────────────┘
```

#### Bảng so sánh ArgoCD vs Flux

| Tiêu chí | ArgoCD | Flux |
|---|---|---|
| **UI** | Web UI đẹp, trực quan | Không có UI mặc định (dùng Weave GitOps) |
| **Cài đặt** | Single `kubectl apply` | Flux CLI bootstrap |
| **App model** | `Application` CRD | `Kustomization` + `HelmRelease` CRD |
| **Multi-tenant** | `AppProject` | `Tenant` (Flux v2) |
| **Notification** | Built-in | Notification Controller |
| **Helm support** | Tốt | Tốt (HelmRelease) |
| **Kustomize support** | Tốt | Native |
| **Learning curve** | Thấp hơn (UI giúp debug) | Cao hơn một chút |
| **Phổ biến** | ⭐ Rất phổ biến | ⭐ Phổ biến (CNCF graduated) |

> **Chọn ArgoCD khi:** team mới, cần UI debug nhanh.
> **Chọn Flux khi:** muốn CLI-first, GitOps thuần, native Kustomize.

---

### 3. ArgoCD — Các khái niệm cốt lõi

#### Application CRD

```yaml
# argocd/apps/my-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/org/repo.git
    targetRevision: HEAD          # branch / tag / commit SHA
    path: k8s/overlays/prod       # đường dẫn trong repo
  destination:
    server: https://kubernetes.default.svc   # cluster hiện tại
    namespace: my-app-namespace
  syncPolicy:
    automated:
      prune: true        # xóa resource không còn trong Git
      selfHeal: true     # tự sửa khi có drift
    syncOptions:
      - CreateNamespace=true
```

**Các trạng thái quan trọng:**
- `Synced` — cluster khớp với Git ✅
- `OutOfSync` — có drift, chưa sync ⚠️
- `Degraded` — resource không healthy ❌
- `Progressing` — đang deploy 🔄

#### App-of-Apps Pattern

```
argocd/
  root-app.yaml          ← ArgoCD quản lý cái này
  apps/
    prometheus.yaml      ← ArgoCD Application cho Prometheus
    my-app.yaml          ← ArgoCD Application cho app của bạn
    cert-manager.yaml    ← ArgoCD Application cho cert-manager
```

**Root app trỏ vào thư mục `apps/` → ArgoCD tự discover và quản lý tất cả app con.**

```yaml
# root-app.yaml — "App that manages apps"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
spec:
  source:
    repoURL: https://github.com/org/repo.git
    path: argocd/apps          # thư mục chứa các Application YAML
    targetRevision: HEAD
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
```

#### Sync Waves — Kiểm soát thứ tự deploy

```yaml
# Dùng annotation để chỉ định thứ tự
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"   # CRD cài trước (wave 0)
    # argocd.argoproj.io/sync-wave: "1" # Operator (wave 1)
    # argocd.argoproj.io/sync-wave: "2" # Application (wave 2)
```

**Thứ tự thực tế:**
1. Wave 0: CRDs, Namespaces
2. Wave 1: Operators, RBAC
3. Wave 2: Applications phụ thuộc (DB, cache)
4. Wave 3: Applications chính

---

### 4. GitHub Actions — CI/CD Pipeline

#### Mô hình Plan-on-PR / Apply-on-Merge

```
Developer → PR → GitHub Actions: validate + plan → Review → Merge → Apply
```

#### Workflow Plan-on-PR (chạy khi mở PR)

```yaml
# .github/workflows/plan.yaml
name: Plan on PR

on:
  pull_request:
    branches: [main]
    paths:
      - 'k8s/**'
      - 'argocd/**'

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install kubeval
        run: |
          wget https://github.com/instrumenta/kubeval/releases/latest/download/kubeval-linux-amd64.tar.gz
          tar xf kubeval-linux-amd64.tar.gz
          sudo mv kubeval /usr/local/bin

      - name: Validate Kubernetes manifests
        run: kubeval --strict k8s/**/*.yaml

      - name: Dry-run with kubectl
        run: |
          kubectl apply --dry-run=client -f k8s/ --recursive

      - name: Comment PR with validation result
        uses: actions/github-script@v7
        with:
          script: |
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: '✅ Validation passed. Ready to merge.'
            })
```

#### Workflow Apply-on-Merge (chạy khi merge vào main)

```yaml
# .github/workflows/apply.yaml
name: Apply on Merge

on:
  push:
    branches: [main]
    paths:
      - 'k8s/**'
      - 'argocd/**'

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Trigger ArgoCD sync
        run: |
          argocd app sync my-app \
            --server ${{ secrets.ARGOCD_SERVER }} \
            --auth-token ${{ secrets.ARGOCD_TOKEN }} \
            --prune \
            --force

      - name: Wait for sync
        run: |
          argocd app wait my-app \
            --health \
            --timeout 300
```

> **Lưu ý:** Với GitOps thuần (ArgoCD automated sync), bạn **không cần** bước Apply — ArgoCD tự detect khi `main` thay đổi. Trigger ArgoCD sync chỉ dùng khi cần force sync ngay lập tức.

---

### 5. Rollback Strategies — Quan trọng!

#### So sánh 2 phương pháp

| | `git revert` | `kubectl rollout undo` |
|---|---|---|
| **Bản chất** | Tạo commit mới đảo ngược thay đổi | Rollback deployment về revision trước |
| **GitOps compliant** | ✅ Có (Git vẫn là source of truth) | ❌ Không (bypass Git, drift ngay lập tức) |
| **Audit trail** | ✅ Đầy đủ trong Git history | ❌ Không có trong Git |
| **Khi dùng** | Production incidents, rollback lâu dài | **Không dùng khi có GitOps** |
| **Nguy cơ** | Cần review lại conflict | ArgoCD sẽ sync lại → override rollback! |

#### Quy trình rollback đúng với GitOps

```bash
# 1. Xác định commit cần revert
git log --oneline -10

# 2. Revert commit (tạo commit mới)
git revert <commit-sha> --no-edit

# 3. Push lên main (hoặc tạo PR nếu có branch protection)
git push origin main

# 4. ArgoCD tự detect thay đổi và sync
# Hoặc force sync ngay:
argocd app sync my-app
```

> ⚠️ **CẢNH BÁO:** Nếu dùng `kubectl rollout undo` trong môi trường có ArgoCD automated sync, ArgoCD sẽ phát hiện drift và sync lại — override rollback của bạn trong vòng vài phút!

---

## 🔗 Tài liệu tham khảo

| Tài liệu | Link | Ưu tiên |
|---|---|---|
| ArgoCD Getting Started | https://argo-cd.readthedocs.io/en/stable/getting_started | ⭐⭐⭐ Đọc trước |
| ArgoCD App of Apps | https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping | ⭐⭐⭐ Quan trọng |
| OpenGitOps Principles | https://opengitops.dev | ⭐⭐ Nền tảng |
| GitHub Actions Docs | https://docs.github.com/en/actions | ⭐⭐ Thực hành |
| Flux Docs | https://fluxcd.io/flux | ⭐ Tham khảo thêm |

---

## 🏗️ Cấu trúc thư mục thực hành

```
cloud/w9/day-a/
├── .github/
│   └── workflows/
│       ├── plan.yaml          # Validate on PR
│       └── apply.yaml         # Sync on merge
├── argocd/
│   ├── install/
│   │   └── argocd-install.yaml
│   ├── root-app.yaml          # App-of-Apps root
│   └── apps/
│       ├── my-app.yaml
│       └── monitoring.yaml
└── k8s/
    ├── base/
    │   ├── deployment.yaml
    │   ├── service.yaml
    │   └── kustomization.yaml
    └── overlays/
        ├── dev/
        └── prod/
```

---

## ✅ Checklist tự kiểm tra

- [ ] Giải thích được 4 nguyên tắc GitOps (Declarative, Versioned, Pulled, Reconciled)
- [ ] Phân biệt push model vs pull model
- [ ] Viết được ArgoCD `Application` CRD từ đầu
- [ ] Hiểu App-of-Apps: root app trỏ vào folder apps/
- [ ] Dùng sync wave annotation để kiểm soát thứ tự
- [ ] Cấu hình GitHub Actions plan-on-PR + apply-on-merge
- [ ] Biết tại sao KHÔNG dùng `kubectl rollout undo` khi có ArgoCD
- [ ] Thực hiện rollback đúng cách qua `git revert`

---

## 📝 Ghi chú cá nhân

<!-- Ghi lại những điểm khó hiểu, câu hỏi cần hỏi mentor -->

**Câu hỏi / Vướng mắc:**

**Điểm đã hiểu rõ:**

**Kế hoạch thực hành:**
