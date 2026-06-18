# Image Security Runbook

## Tổng quan

Pipeline bảo mật image gồm 3 lớp:
1. **Trivy** — quét CVE trước khi push
2. **Cosign** — ký image sau khi push
3. **Policy Controller** — block image chưa ký khi deploy

---

## 1. Trivy Image Scan

### Mục đích

Phát hiện CVE mức **HIGH** và **CRITICAL** trong image trước khi push lên registry.

### Cách hoạt động trong CI

```yaml
# .github/workflows/build-push.yml
- name: Scan image with Trivy
  uses: aquasecurity/trivy-action@0.24.0
  with:
    image-ref: ghcr.io/OWNER/IMAGE:VERSION
    severity: 'HIGH,CRITICAL'
    exit-code: '1'     # CI FAIL nếu có CVE
    ignore-unfixed: false
```

### Chạy Trivy thủ công (local)

```bash
# Cài Trivy:
brew install trivy          # macOS
# hoặc: https://aquasecurity.github.io/trivy/latest/getting-started/installation/

# Scan image local:
trivy image \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  ghcr.io/nhatphanhk/w10-api:latest

# Scan với output dạng JSON:
trivy image \
  --severity HIGH,CRITICAL \
  --format json \
  --output trivy-results.json \
  ghcr.io/nhatphanhk/w10-api:latest

# Scan file system của repo:
trivy fs \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  ./src/api
```

### Kết quả scan

- **Exit 0**: Không có HIGH/CRITICAL CVE → CI tiếp tục push
- **Exit 1**: Có CVE → CI FAIL, image KHÔNG được push

---

## 2. Cosign Image Signing

### Mục đích

Ký image bằng private key sau khi Trivy pass. Signature được push cùng image lên registry.

### Setup một lần

```bash
# Cài cosign:
brew install cosign          # macOS
# hoặc: https://docs.sigstore.dev/cosign/system_config/installation/

# Generate key pair:
cd cloud/w10/lab_day4
cosign generate-key-pair

# Kết quả:
# - cosign.key  → PRIVATE KEY → copy vào GitHub Secret: COSIGN_PRIVATE_KEY
# - cosign.pub  → PUBLIC KEY  → commit vào signing/cosign.pub

# Di chuyển public key vào thư mục signing:
mv cosign.pub signing/cosign.pub

# TUYỆT ĐỐI không commit cosign.key
# Thêm vào .gitignore:
echo "cosign.key" >> .gitignore
```

### Lưu private key vào GitHub Secrets

```
GitHub Repo → Settings → Secrets and variables → Actions → New repository secret

Tên:  COSIGN_PRIVATE_KEY
Giá trị: (nội dung file cosign.key)

Tên:  COSIGN_PASSWORD
Giá trị: (passphrase đã nhập khi generate-key-pair)
```

### Ký image thủ công (local)

```bash
# Ký bằng digest (immutable, recommended):
IMAGE_DIGEST=$(docker buildx imagetools inspect \
  ghcr.io/nhatphanhk/w10-api:latest \
  --format '{{.Manifest.Digest}}')

cosign sign \
  --key cosign.key \
  "ghcr.io/nhatphanhk/w10-api@${IMAGE_DIGEST}"
```

### Verify signature

```bash
# Verify bằng public key:
cosign verify \
  --key signing/cosign.pub \
  ghcr.io/nhatphanhk/w10-api:latest \
  | jq .

# Output thành công:
# [{"critical":{"identity":{"docker-reference":"ghcr.io/..."},...}]
```

---

## 3. Admission Verification (Policy Controller)

### Mục đích

Block các pod dùng image chưa được ký từ deploy vào namespace được bảo vệ.

### Gắn label namespace

```bash
# Bật enforcement cho namespace demo:
kubectl label namespace demo policy.sigstore.dev/include=true

# Verify:
kubectl get namespace demo --show-labels
```

### Test Case 1: Deploy image CHƯA ký → REJECT

```bash
# Deploy một image không có signature:
kubectl run test-unsigned \
  --image=nginx:latest \
  -n demo

# Expected output (REJECT):
# Error from server: admission webhook "policy.sigstore.dev" denied the request:
# image nginx:latest did not match any authority
```

### Test Case 2: Deploy image ĐÃ ký từ CI → PASS

```bash
# Deploy image đã được CI ký:
kubectl run test-signed \
  --image=ghcr.io/nhatphanhk/w10-api:latest \
  -n demo

# Expected: Pod tạo thành công (PASS)
kubectl get pod test-signed -n demo
```

### Xem Policy Controller logs

```bash
kubectl logs -n cosign-system \
  -l app=policy-controller \
  --tail=50
```

---

## CI/CD Flow Summary

```
git push
    │
    ▼
docker build (local, no push)
    │
    ▼
trivy scan (HIGH/CRITICAL)
    ├── FAIL → CI stop ❌
    └── PASS ↓
         │
         ▼
    docker push to ghcr.io
         │
         ▼
    cosign sign (by digest)
         │
         ▼
    signature pushed to ghcr.io
         │
         ▼
    ArgoCD sync → Policy Controller verify ✅
```
