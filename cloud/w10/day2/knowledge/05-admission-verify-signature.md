# 05 — Admission Webhook Verify Signature

> **Scope:** Kyverno verify images, Connaisseur, policy config, reject unsigned images

---

## 1. Tại sao verify ở Admission?

Signing ở CI chỉ đảm bảo image **đã được ký**. Nhưng nếu ai đó bypass CI và push image trực tiếp vào registry? Cần **gate ở cluster level** — admission webhook verify trước khi cho deploy.

```
Without admission verify:
  CI: sign ✅ → push to registry
  Manual: push unsigned → kubectl apply → Pod runs ❌ (no verification)

With admission verify:
  CI: sign ✅ → push to registry → deploy → verify ✅ → Pod runs ✅
  Manual: push unsigned → kubectl apply → verify ❌ → REJECTED
```

---

## 2. Kyverno Verify Images (Recommended)

**Kyverno** = Kubernetes-native policy engine (alternative to Gatekeeper). Có built-in **verifyImages** rule type.

### Install Kyverno

```bash
helm repo add kyverno https://kyverno.github.io/kyverno
helm repo update

helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace \
  --set replicaCount=3

# Verify
kubectl get pods -n kyverno
```

### Policy: Verify Cosign Keyless Signature

```yaml
# verify-image-keyless.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-image-signature
  annotations:
    policies.kyverno.io/title: Verify Image Signatures
    policies.kyverno.io/description: |
      Chỉ cho phép deploy images được ký bởi CI/CD pipeline
      của tổ chức (GitHub Actions keyless OIDC).
spec:
  validationFailureAction: Enforce    # Enforce | Audit
  background: true                     # Scan existing resources
  webhookTimeoutSeconds: 30
  rules:
    - name: verify-cosign-keyless
      match:
        any:
          - resources:
              kinds:
                - Pod
              namespaces:
                - production
                - staging
      verifyImages:
        - imageReferences:
            - "123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/*"
          attestors:
            - entries:
                - keyless:
                    subject: "https://github.com/myorg/*"
                    issuer: "https://token.actions.githubusercontent.com"
                    rekor:
                      url: https://rekor.sigstore.dev
          mutateDigest: true            # Replace tag → digest
          verifyDigest: true            # Verify digest matches
          required: true                # Phải có signature
```

### Policy: Verify Key-based Signature

```yaml
# verify-image-key.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-image-key-signature
spec:
  validationFailureAction: Enforce
  rules:
    - name: verify-cosign-key
      match:
        any:
          - resources:
              kinds: ["Pod"]
              namespaces: ["production"]
      verifyImages:
        - imageReferences:
            - "123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/*"
          attestors:
            - entries:
                - keys:
                    publicKeys: |
                      -----BEGIN PUBLIC KEY-----
                      MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE...
                      -----END PUBLIC KEY-----
                    # Hoặc reference từ Secret/ConfigMap:
                    # secret:
                    #   name: cosign-pub-key
                    #   namespace: kyverno
          required: true
```

### Policy: Verify Attestation (Scan Results)

```yaml
# verify-attestation.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-vulnerability-scan
spec:
  validationFailureAction: Enforce
  rules:
    - name: check-vuln-attestation
      match:
        any:
          - resources:
              kinds: ["Pod"]
              namespaces: ["production"]
      verifyImages:
        - imageReferences:
            - "123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/*"
          attestations:
            - type: https://cosign.sigstore.dev/attestation/vuln/v1
              attestors:
                - entries:
                    - keyless:
                        subject: "https://github.com/myorg/*"
                        issuer: "https://token.actions.githubusercontent.com"
              conditions:
                - all:
                    # Check scan results có 0 CRITICAL vulnerabilities
                    - key: "{{ Results[].Vulnerabilities[?Severity=='CRITICAL'] | length(@) }}"
                      operator: Equals
                      value: 0
```

---

## 3. Exception Handling

### Skip verification cho specific images

```yaml
# exceptions.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-image-signature
spec:
  validationFailureAction: Enforce
  rules:
    - name: verify-cosign-keyless
      match:
        any:
          - resources:
              kinds: ["Pod"]
      exclude:
        any:
          # Exclude system namespaces
          - resources:
              namespaces:
                - kube-system
                - kyverno
                - gatekeeper-system
                - monitoring
                - external-secrets
          # Exclude specific images (third-party, không ký được)
          - resources:
              kinds: ["Pod"]
            # Dùng preconditions cho image matching
      preconditions:
        all:
          # Chỉ verify images từ ECR của chúng ta
          - key: "{{ request.object.spec.containers[].image }}"
            operator: AnyIn
            value:
              - "123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/*"
      verifyImages:
        - imageReferences:
            - "123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/*"
          attestors:
            - entries:
                - keyless:
                    subject: "https://github.com/myorg/*"
                    issuer: "https://token.actions.githubusercontent.com"
          required: true
```

### Kyverno PolicyException (K8s CRD)

```yaml
# policy-exception.yaml
apiVersion: kyverno.io/v2
kind: PolicyException
metadata:
  name: allow-legacy-app-unsigned
  namespace: production
  annotations:
    exception.platform.io/reason: "Legacy app migrating, chưa có CI signing"
    exception.platform.io/ticket: "SEC-789"
    exception.platform.io/expires: "2024-03-01"
    exception.platform.io/owner: "alice@company.com"
spec:
  exceptions:
    - policyName: verify-image-signature
      ruleNames:
        - verify-cosign-keyless
  match:
    any:
      - resources:
          kinds: ["Pod"]
          namespaces: ["production"]
          names: ["legacy-app-*"]
```

---

## 4. Audit Mode — Phát hiện unsigned images

```yaml
# Bước 1: Deploy policy ở Audit mode
spec:
  validationFailureAction: Audit     # Không block, chỉ log

# Bước 2: Kiểm tra violations
kubectl get policyreport -A
kubectl get clusterpolicyreport

# Bước 3: Xem chi tiết
kubectl get policyreport -n production -o yaml
# status:
#   results:
#     - policy: verify-image-signature
#       rule: verify-cosign-keyless  
#       result: fail
#       resources:
#         - name: legacy-app-xxx
#           kind: Pod
#           namespace: production
#       message: "image signature verification failed"

# Bước 4: Fix all violations → chuyển Enforce
```

---

## 5. Verify Flow Diagram

```
kubectl apply -f deployment.yaml
        │
        ▼
┌─────────────────────────────────────┐
│  K8s API Server                      │
│         │                            │
│         ▼                            │
│  Mutating Admission                  │
│  (Kyverno mutate tag → digest)       │
│         │                            │
│         ▼                            │
│  Validating Admission                │
│  ┌────────────────────────────────┐  │
│  │  Kyverno verifyImages:        │  │
│  │                               │  │
│  │  1. Extract image digest      │  │
│  │  2. Fetch signature from      │  │
│  │     registry (OCI artifact)   │  │
│  │  3. Verify signature against  │  │
│  │     attestor (keyless/key)    │  │
│  │  4. Check certificate:        │  │
│  │     - identity matches?       │  │
│  │     - issuer matches?         │  │
│  │     - not expired?            │  │
│  │  5. Check Rekor log entry     │  │
│  │                               │  │
│  │  ✅ All pass → ALLOW          │  │
│  │  ❌ Any fail → DENY           │  │
│  └────────────────────────────────┘  │
│         │                            │
│         ▼                            │
│  Persist to etcd                     │
└─────────────────────────────────────┘
```

---

## 6. Monitoring

```bash
# Kyverno metrics (Prometheus)
# kyverno_policy_results_total{policy_name, rule_name, result}
# result = "pass" | "fail" | "warn" | "error" | "skip"

# Alert khi có unsigned image attempts
# PromQL:
rate(kyverno_policy_results_total{
  policy_name="verify-image-signature",
  result="fail"
}[5m]) > 0
```
