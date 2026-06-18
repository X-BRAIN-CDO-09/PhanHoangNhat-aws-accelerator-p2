# 01 — Platform Integration (W8→W10)

> **Scope:** Tích hợp toàn bộ stack, bootstrap script, dependency order, < 2h deployment

---

## 1. Platform Components — Dependency Map

```
Layer 0: Infrastructure (W8 — Terraform)
├── EKS Cluster
├── VPC / Subnets / NAT
├── ECR Repositories
├── IAM Roles (IRSA)
└── KMS Keys

Layer 1: Core Platform (W8-W9)
├── cert-manager          → TLS certificates
├── external-dns          → Route53 DNS records
├── ingress-nginx         → Ingress controller
└── metrics-server        → HPA prerequisite

Layer 2: GitOps + Observability (W9)
├── ArgoCD                → GitOps deployment
├── Prometheus + Grafana  → Metrics + dashboards
├── AlertManager          → Alert routing
└── Loki                  → Log aggregation

Layer 3: Security + Policy (W10)
├── Gatekeeper            → Admission policies
├── External Secrets Op.  → Secrets sync
├── Kyverno (optional)    → Image verification
└── RBAC                  → Access control

Layer 4: Namespace Config
├── Namespaces            → Team isolation
├── ResourceQuota         → Resource limits
├── LimitRange            → Container defaults
├── NetworkPolicy         → Network isolation
└── RoleBindings          → Team access
```

---

## 2. Bootstrap Order — Dependency Chain

```bash
# ⚠️ THỨ TỰ RẤT QUAN TRỌNG — deploy sai order = fail

# Phase 0: Infrastructure (Terraform — đã deploy W8)
# terraform apply → EKS + VPC + IAM

# Phase 1: Core Platform
kubectl apply -f 00-namespaces.yaml          # Namespaces trước
helm install cert-manager ...                 # TLS certs
helm install ingress-nginx ...                # Ingress
helm install external-dns ...                 # DNS
kubectl apply -f metrics-server.yaml          # HPA needs this

# Phase 2: GitOps + Observability
helm install argocd ...                       # GitOps
helm install kube-prometheus-stack ...         # Prometheus + Grafana + AlertManager
helm install loki-stack ...                   # Logs

# Phase 3: Security (W10)
helm install gatekeeper ...                   # Policy engine
# → Deploy constraints ở dryrun trước!
helm install external-secrets ...             # Secrets sync
kubectl apply -f rbac/                        # RBAC roles + bindings

# Phase 4: Namespace Config
kubectl apply -f quotas/                      # ResourceQuota + LimitRange
kubectl apply -f network-policies/            # NetworkPolicy
kubectl apply -f external-secrets/            # ExternalSecrets per namespace

# Phase 5: Applications (via ArgoCD)
kubectl apply -f argocd-apps/                 # ArgoCD Application CRDs
```

---

## 3. Bootstrap Script

```bash
#!/bin/bash
# bootstrap.sh — Deploy entire platform stack
# Usage: ./bootstrap.sh <environment> [--skip-infra]
# Time target: < 2 hours from scratch

set -euo pipefail

ENV="${1:-staging}"
SKIP_INFRA="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================"
echo "  Platform Bootstrap — $ENV"
echo "  Started: $(date)"
echo "============================================"

# --- Phase 0: Infrastructure ---
if [ "$SKIP_INFRA" != "--skip-infra" ]; then
  echo ""
  echo "📦 Phase 0: Infrastructure (Terraform)"
  cd "$SCRIPT_DIR/../../w8/terraform"
  terraform init
  terraform apply -var="environment=$ENV" -auto-approve
  
  # Get EKS credentials
  aws eks update-kubeconfig \
    --name "platform-$ENV" \
    --region ap-southeast-1
fi

echo ""
echo "📦 Phase 1: Core Platform"

# Namespaces
kubectl apply -f "$SCRIPT_DIR/00-namespaces.yaml"
echo "  ✅ Namespaces created"

# cert-manager
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set installCRDs=true \
  --wait --timeout 5m
echo "  ✅ cert-manager installed"

# ingress-nginx
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.replicaCount=2 \
  --wait --timeout 5m
echo "  ✅ ingress-nginx installed"

echo ""
echo "📦 Phase 2: Observability"

# kube-prometheus-stack (Prometheus + Grafana + AlertManager)
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  --values "$SCRIPT_DIR/../../w9/helm-values/prometheus-values.yaml" \
  --wait --timeout 10m
echo "  ✅ Prometheus stack installed"

echo ""
echo "📦 Phase 3: Security (W10)"

# Gatekeeper
helm upgrade --install gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system --create-namespace \
  --set replicas=3 \
  --set audit.replicas=1 \
  --wait --timeout 5m
echo "  ✅ Gatekeeper installed"

# Gatekeeper constraints (dryrun initially)
kubectl apply -f "$SCRIPT_DIR/02-gatekeeper.yaml"
echo "  ✅ Gatekeeper constraints applied (dryrun)"

# External Secrets Operator
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets --create-namespace \
  --set installCRDs=true \
  --wait --timeout 5m
echo "  ✅ External Secrets Operator installed"

# ESO SecretStore + ExternalSecrets
kubectl apply -f "$SCRIPT_DIR/03-eso.yaml"
echo "  ✅ SecretStore + ExternalSecrets configured"

# RBAC
kubectl apply -f "$SCRIPT_DIR/01-rbac.yaml"
echo "  ✅ RBAC roles + bindings applied"

echo ""
echo "📦 Phase 4: Namespace Config"

# ResourceQuota + LimitRange
kubectl apply -f "$SCRIPT_DIR/04-quotas.yaml"
echo "  ✅ ResourceQuota + LimitRange applied"

echo ""
echo "📦 Phase 5: ArgoCD + Applications"

# ArgoCD
helm upgrade --install argocd argo/argo-cd \
  --namespace argocd --create-namespace \
  --set server.service.type=LoadBalancer \
  --wait --timeout 5m
echo "  ✅ ArgoCD installed"

echo ""
echo "============================================"
echo "  ✅ Platform Bootstrap Complete!"
echo "  Finished: $(date)"
echo "============================================"
echo ""
echo "  Next steps:"
echo "  1. ArgoCD UI: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  2. Grafana: kubectl port-forward svc/monitoring-grafana -n monitoring 3000:80"
echo "  3. Deploy apps via ArgoCD Application CRDs"
```

---

## 4. Verification Script

```bash
#!/bin/bash
# verify-platform.sh — Verify all platform components

echo "=== Platform Health Check ==="
echo ""

# Namespaces
echo "📁 Namespaces:"
for ns in production staging dev monitoring argocd gatekeeper-system external-secrets; do
  if kubectl get ns $ns &>/dev/null; then
    echo "  ✅ $ns"
  else
    echo "  ❌ $ns MISSING"
  fi
done

echo ""
echo "🔐 RBAC:"
for role in developer sre viewer; do
  if kubectl get clusterrole $role &>/dev/null; then
    echo "  ✅ ClusterRole: $role"
  else
    echo "  ❌ ClusterRole: $role MISSING"
  fi
done

echo ""
echo "🛡️ Gatekeeper:"
CONSTRAINTS=$(kubectl get constraints --no-headers 2>/dev/null | wc -l)
VIOLATIONS=$(kubectl get constraints -o jsonpath='{range .items[*]}{.status.totalViolations}{"\n"}{end}' 2>/dev/null | awk '{s+=$1} END {print s}')
echo "  Constraints: $CONSTRAINTS"
echo "  Total violations: ${VIOLATIONS:-0}"

echo ""
echo "🔑 External Secrets:"
SYNCED=$(kubectl get externalsecret -A --no-headers 2>/dev/null | grep "SecretSynced" | wc -l)
TOTAL=$(kubectl get externalsecret -A --no-headers 2>/dev/null | wc -l)
echo "  Synced: $SYNCED / $TOTAL"

echo ""
echo "📊 Monitoring:"
for deploy in prometheus-kube-prometheus-operator prometheus-grafana alertmanager-prometheus-kube-prometheus-alertmanager; do
  if kubectl get deploy $deploy -n monitoring &>/dev/null; then
    READY=$(kubectl get deploy $deploy -n monitoring -o jsonpath='{.status.readyReplicas}')
    echo "  ✅ $deploy (ready: $READY)"
  fi
done

echo ""
echo "🚀 ArgoCD:"
if kubectl get deploy argocd-server -n argocd &>/dev/null; then
  APPS=$(kubectl get applications -n argocd --no-headers 2>/dev/null | wc -l)
  HEALTHY=$(kubectl get applications -n argocd --no-headers 2>/dev/null | grep "Healthy" | wc -l)
  echo "  ✅ ArgoCD running"
  echo "  Apps: $APPS (healthy: $HEALTHY)"
fi

echo ""
echo "=== Health Check Complete ==="
```

---

## 5. Platform as Code — File Layout

```
repo/
├── infrastructure/           # W8 — Terraform
│   ├── eks/
│   ├── vpc/
│   ├── iam/
│   └── ecr/
│
├── platform/                 # W9-W10 — K8s manifests
│   ├── base/                 # Shared across envs
│   │   ├── namespaces/
│   │   ├── rbac/
│   │   ├── gatekeeper/
│   │   ├── eso/
│   │   ├── quotas/
│   │   └── network-policies/
│   │
│   ├── overlays/             # Kustomize overlays
│   │   ├── staging/
│   │   └── production/
│   │
│   └── helm-values/          # Helm value files
│       ├── argocd-values.yaml
│       ├── prometheus-values.yaml
│       └── gatekeeper-values.yaml
│
├── apps/                     # Application manifests
│   ├── myapp/
│   └── api-gateway/
│
└── scripts/
    ├── bootstrap.sh
    └── verify.sh
```
