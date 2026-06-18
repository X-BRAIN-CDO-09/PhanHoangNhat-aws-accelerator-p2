# 04 — Cosign Image Signing

> **Scope:** Keyless OIDC signing, key-based signing, verify, Sigstore/Rekor transparency log

---

## 1. Cosign là gì?

**Cosign** (part of Sigstore project) = tool để **ký (sign)** và **xác minh (verify)** container images. Đảm bảo: "Image này thực sự được build từ CI/CD pipeline của chúng ta, không bị tamper."

```
┌─────────────────────────────────────────────────────────┐
│                     CI Pipeline                          │
│                                                          │
│  Build ──► Scan ──► Push ──► COSIGN SIGN ──► Registry   │
│                                  │                       │
│                                  │ signature              │
│                                  ▼                       │
│                          ┌──────────────┐                │
│                          │ OCI Registry │                │
│                          │              │                │
│                          │ myapp:v1.0   │ ← image       │
│                          │ myapp:sha256 │                │
│                          │ -xxxx.sig    │ ← signature   │
│                          └──────────────┘                │
│                                                          │
│  Deploy ──► Admission Verify ──► COSIGN VERIFY ──► ✅/❌│
└─────────────────────────────────────────────────────────┘
```

---

## 2. Hai mode signing

### Mode 1: Keyless OIDC (Recommended for CI/CD)

Không cần quản lý key pair. Dùng **OIDC identity** từ CI provider (GitHub Actions, GitLab CI).

```
Keyless flow:
1. CI pipeline request OIDC token từ provider (GitHub/GitLab)
2. Cosign gửi token đến Fulcio (certificate authority)
3. Fulcio issue short-lived certificate (10 phút)
4. Cosign ký image bằng certificate
5. Signature + certificate được log vào Rekor (transparency log)
6. Verify: kiểm tra certificate identity + OIDC issuer
```

```bash
# Sign (trong GitHub Actions — tự động có OIDC token)
cosign sign --yes \
  123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/myapp:v1.0

# Verify
cosign verify \
  --certificate-identity "https://github.com/myorg/myrepo/.github/workflows/build.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/myapp:v1.0
```

### Mode 2: Key-based (Traditional)

Quản lý key pair riêng. Phù hợp cho air-gapped environments.

```bash
# Generate key pair
cosign generate-key-pair
# Output: cosign.key (private) + cosign.pub (public)
# ⚠️ Lưu private key trong Secrets Manager, KHÔNG commit vào Git

# Sign
cosign sign --key cosign.key \
  123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/myapp:v1.0

# Verify
cosign verify --key cosign.pub \
  123456789012.dkr.ecr.ap-southeast-1.amazonaws.com/myapp:v1.0
```

### So sánh

| Feature | Keyless OIDC | Key-based |
|---|---|---|
| Key management | ❌ Không cần | ✅ Phải quản lý private key |
| Air-gapped | ❌ Cần internet (Fulcio/Rekor) | ✅ Offline OK |
| Audit trail | ✅ Rekor transparency log | ⚠️ Tự log |
| Identity verification | ✅ Verify WHO signed | ⚠️ Verify key, không biết WHO |
| Rotation | ✅ Certificate auto-expire | ❌ Manual key rotation |
| CI/CD | ✅ Perfect fit | ⚠️ Key trong CI secrets |

---

## 3. Sigstore Components

```
┌─────────────────────────────────────────────────────┐
│                    Sigstore Ecosystem                 │
│                                                       │
│  ┌───────────┐   ┌───────────┐   ┌───────────────┐  │
│  │  Cosign   │   │  Fulcio   │   │    Rekor      │  │
│  │           │   │           │   │               │  │
│  │ Sign &    │──►│ Certificate│──►│ Transparency  │  │
│  │ Verify    │   │ Authority │   │ Log           │  │
│  │ tool      │   │ (OIDC→cert)│   │ (immutable)   │  │
│  └───────────┘   └───────────┘   └───────────────┘  │
│                                                       │
│  cosign sign     Fulcio issues    Rekor stores       │
│  cosign verify   short-lived      signature +        │
│                  certificate      certificate        │
│                  (10 min)         permanently         │
└─────────────────────────────────────────────────────┘
```

---

## 4. GitHub Actions — Keyless Signing

```yaml
# .github/workflows/sign.yaml
name: Build, Scan & Sign

on:
  push:
    branches: [main]
    tags: ['v*']

permissions:
  contents: read
  id-token: write              # ← BẮT BUỘC cho keyless OIDC
  packages: write

env:
  REGISTRY: 123456789012.dkr.ecr.ap-southeast-1.amazonaws.com
  IMAGE: myapp

jobs:
  build-sign:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Install Cosign
        uses: sigstore/cosign-installer@v3
      
      - name: Configure AWS
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
          aws-region: ap-southeast-1
      
      - name: Login ECR
        uses: aws-actions/amazon-ecr-login@v2
      
      - name: Build & Push
        id: build
        run: |
          IMAGE_TAG=$REGISTRY/$IMAGE:${{ github.sha }}
          docker build -t $IMAGE_TAG .
          docker push $IMAGE_TAG
          
          # Get digest for signing
          DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' $IMAGE_TAG)
          echo "digest=$DIGEST" >> $GITHUB_OUTPUT
      
      - name: Sign image (keyless)
        run: |
          cosign sign --yes ${{ steps.build.outputs.digest }}
        env:
          COSIGN_EXPERIMENTAL: "true"
      
      - name: Verify signature
        run: |
          cosign verify \
            --certificate-identity "https://github.com/${{ github.repository }}/.github/workflows/sign.yaml@refs/heads/main" \
            --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
            ${{ steps.build.outputs.digest }}
```

---

## 5. Key-based Signing — Với KMS

Lưu private key trong AWS KMS (không lưu local):

```bash
# Tạo key pair dùng AWS KMS
cosign generate-key-pair --kms awskms:///alias/cosign-key

# Sign dùng KMS key
cosign sign --key awskms:///alias/cosign-key \
  $REGISTRY/$IMAGE:$TAG

# Verify (chỉ cần public key)
cosign verify --key awskms:///alias/cosign-key \
  $REGISTRY/$IMAGE:$TAG

# Hoặc export public key
cosign public-key --key awskms:///alias/cosign-key > cosign.pub
cosign verify --key cosign.pub $REGISTRY/$IMAGE:$TAG
```

### KMS Key Terraform

```hcl
resource "aws_kms_key" "cosign" {
  description             = "Cosign image signing key"
  key_usage               = "SIGN_VERIFY"
  customer_master_key_spec = "ECC_NIST_P256"    # Cosign requirement
  deletion_window_in_days = 7
  
  tags = {
    Purpose = "container-image-signing"
    Team    = "platform"
  }
}

resource "aws_kms_alias" "cosign" {
  name          = "alias/cosign-key"
  target_key_id = aws_kms_key.cosign.key_id
}
```

---

## 6. Attach Attestations

Ngoài signature, Cosign có thể attach **attestations** (metadata) vào image:

```bash
# Attach vulnerability scan results
cosign attest --yes \
  --predicate trivy-results.json \
  --type vuln \
  $REGISTRY/$IMAGE:$TAG

# Attach SBOM
cosign attest --yes \
  --predicate sbom.cyclonedx.json \
  --type cyclonedx \
  $REGISTRY/$IMAGE:$TAG

# Verify attestation
cosign verify-attestation \
  --certificate-identity "https://github.com/myorg/myrepo/.github/workflows/build.yml@refs/heads/main" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  --type vuln \
  $REGISTRY/$IMAGE:$TAG
```

---

## 7. Verify Commands Cheat Sheet

```bash
# Verify keyless signature
cosign verify \
  --certificate-identity "https://github.com/OWNER/REPO/.github/workflows/WORKFLOW@refs/heads/BRANCH" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  IMAGE

# Verify keyless với identity regex
cosign verify \
  --certificate-identity-regexp "https://github.com/myorg/.*" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  IMAGE

# Verify key-based
cosign verify --key cosign.pub IMAGE
cosign verify --key awskms:///alias/cosign-key IMAGE

# Verify và xem certificate details
cosign verify ... IMAGE | jq '.[].optional'

# Check Rekor transparency log
cosign verify ... IMAGE | jq '.[].optional.Bundle.Payload.logIndex'
# → Tìm log entry tại: https://search.sigstore.dev
```

---

## 8. SLSA Supply Chain Levels

Cosign signing là bước đầu tiên trong **SLSA (Supply chain Levels for Software Artifacts)**:

| Level | Yêu cầu | Cosign role |
|---|---|---|
| SLSA 1 | Build process documented | ✅ Attestation |
| SLSA 2 | Hosted build, signed provenance | ✅ Keyless OIDC |
| SLSA 3 | Hardened build platform | ✅ + Build isolation |
| SLSA 4 | Two-person review, hermetic build | Beyond Cosign |
