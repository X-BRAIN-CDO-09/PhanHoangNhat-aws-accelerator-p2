# 03 — Trivy Image Scan trong CI

> **Scope:** Trivy scan modes, CI integration (GitHub Actions / GitLab CI), severity policy, SBOM

---

## 1. Trivy là gì?

**Trivy** (by Aqua Security) = all-in-one security scanner. Scan:
- **Container images** — OS packages + language packages CVEs
- **Filesystem** — code dependencies (package-lock.json, go.sum, requirements.txt)
- **IaC** — Terraform, CloudFormation misconfigurations
- **K8s** — cluster & workload misconfiguration
- **SBOM** — Software Bill of Materials

```
┌──────────────────────────────────────────────┐
│                  CI Pipeline                   │
│                                                │
│  Build ──► Trivy Scan ──► Pass/Fail ──► Push  │
│               │                                │
│               ├── CVE-2024-xxxx (CRITICAL) ❌  │
│               ├── CVE-2024-yyyy (HIGH) ❌      │
│               ├── CVE-2024-zzzz (MEDIUM) ⚠️    │
│               └── CVE-2024-wwww (LOW) ℹ️       │
│                                                │
│  Policy: Fail nếu có CRITICAL hoặc HIGH       │
└──────────────────────────────────────────────┘
```

---

## 2. Cài đặt và chạy local

```bash
# macOS
brew install trivy

# Linux
sudo apt-get install -y trivy
# hoặc
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin

# Scan image
trivy image nginx:latest

# Scan với severity filter
trivy image --severity HIGH,CRITICAL nginx:latest

# Scan và fail nếu có HIGH/CRITICAL
trivy image --severity HIGH,CRITICAL --exit-code 1 nginx:latest

# Scan chỉ OS packages (nhanh hơn)
trivy image --vuln-type os nginx:latest

# Scan chỉ language packages
trivy image --vuln-type library myapp:v1.0

# Output formats
trivy image --format json -o results.json nginx:latest
trivy image --format table nginx:latest
trivy image --format sarif -o results.sarif nginx:latest    # GitHub Security tab
trivy image --format template --template "@contrib/html.tpl" -o report.html nginx:latest
```

---

## 3. Severity Levels

| Severity | Ý nghĩa | Action |
|---|---|---|
| **CRITICAL** | Remote code execution, privilege escalation | ❌ Block deploy. Fix ngay. |
| **HIGH** | Significant impact, có exploit | ❌ Block deploy. Fix trong sprint. |
| **MEDIUM** | Limited impact, cần specific conditions | ⚠️ Track. Fix khi convenient. |
| **LOW** | Minimal impact | ℹ️ Log. Fix khi update dependency. |
| **UNKNOWN** | Chưa có severity assessment | ℹ️ Investigate nếu có thời gian. |

### CVSS Score mapping

| CVSS v3 Score | Severity |
|---|---|
| 9.0 - 10.0 | CRITICAL |
| 7.0 - 8.9 | HIGH |
| 4.0 - 6.9 | MEDIUM |
| 0.1 - 3.9 | LOW |

---

## 4. GitHub Actions Integration

```yaml
# .github/workflows/scan-and-sign.yaml
name: Build, Scan & Sign

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

env:
  REGISTRY: 123456789012.dkr.ecr.ap-southeast-1.amazonaws.com
  IMAGE_NAME: myapp

jobs:
  build-scan-sign:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write          # Cho Cosign keyless OIDC
      security-events: write   # Upload SARIF
    
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789012:role/github-actions-ecr
          aws-region: ap-southeast-1
      
      - name: Login to ECR
        uses: aws-actions/amazon-ecr-login@v2
      
      - name: Build image
        run: |
          docker build -t $REGISTRY/$IMAGE_NAME:${{ github.sha }} .
          docker build -t $REGISTRY/$IMAGE_NAME:latest .
      
      # ========================================
      # TRIVY SCAN
      # ========================================
      - name: Trivy vulnerability scan
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: '${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}'
          format: 'table'
          exit-code: '1'                    # Fail pipeline nếu có vulnerability
          ignore-unfixed: true              # Bỏ qua CVE chưa có fix
          vuln-type: 'os,library'
          severity: 'CRITICAL,HIGH'         # Chỉ fail cho CRITICAL + HIGH
          trivyignores: '.trivyignore'      # Exception file
      
      # Upload SARIF to GitHub Security tab
      - name: Trivy SARIF scan
        uses: aquasecurity/trivy-action@master
        if: always()                        # Chạy dù step trước fail
        with:
          image-ref: '${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}'
          format: 'sarif'
          output: 'trivy-results.sarif'
          severity: 'CRITICAL,HIGH,MEDIUM'
      
      - name: Upload SARIF
        uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: 'trivy-results.sarif'
      
      # ========================================
      # PUSH (chỉ khi scan pass)
      # ========================================
      - name: Push image
        run: |
          docker push $REGISTRY/$IMAGE_NAME:${{ github.sha }}
          docker push $REGISTRY/$IMAGE_NAME:latest
      
      # ========================================
      # COSIGN SIGN (sau push)
      # ========================================
      - name: Install Cosign
        uses: sigstore/cosign-installer@v3
      
      - name: Sign image (keyless OIDC)
        run: |
          cosign sign --yes \
            $REGISTRY/$IMAGE_NAME:${{ github.sha }}
        env:
          COSIGN_EXPERIMENTAL: "true"
```

---

## 5. GitLab CI Integration

```yaml
# .gitlab-ci.yml
stages:
  - build
  - scan
  - sign
  - deploy

variables:
  REGISTRY: 123456789012.dkr.ecr.ap-southeast-1.amazonaws.com
  IMAGE_NAME: myapp

build:
  stage: build
  image: docker:24
  services:
    - docker:24-dind
  script:
    - docker build -t $REGISTRY/$IMAGE_NAME:$CI_COMMIT_SHA .
    - docker push $REGISTRY/$IMAGE_NAME:$CI_COMMIT_SHA

trivy-scan:
  stage: scan
  image:
    name: aquasec/trivy:latest
    entrypoint: [""]
  script:
    - trivy image 
        --severity HIGH,CRITICAL 
        --exit-code 1 
        --ignore-unfixed 
        --ignorefile .trivyignore
        --format table
        $REGISTRY/$IMAGE_NAME:$CI_COMMIT_SHA
  allow_failure: false      # Block pipeline nếu fail

trivy-report:
  stage: scan
  image:
    name: aquasec/trivy:latest
    entrypoint: [""]
  script:
    - trivy image 
        --format json 
        -o trivy-report.json
        $REGISTRY/$IMAGE_NAME:$CI_COMMIT_SHA
  artifacts:
    paths:
      - trivy-report.json
    expire_in: 30 days
  allow_failure: true
```

---

## 6. SBOM — Software Bill of Materials

```bash
# Generate SBOM (CycloneDX format)
trivy image --format cyclonedx -o sbom.json myapp:v1.0

# Generate SBOM (SPDX format)
trivy image --format spdx-json -o sbom.spdx.json myapp:v1.0

# Scan SBOM cho vulnerabilities
trivy sbom sbom.json

# Attach SBOM to image (với Cosign)
cosign attach sbom --sbom sbom.json $REGISTRY/$IMAGE_NAME:$CI_COMMIT_SHA
```

### Tại sao cần SBOM?

```
1. Compliance — nhiều regulated industry yêu cầu SBOM
2. Incident Response — khi có CVE mới, biết images nào affected
3. License audit — biết tất cả dependencies + licenses
4. Supply chain transparency — biết chính xác image chứa gì
```

---

## 7. Scan Best Practices

| Practice | Giải thích |
|---|---|
| `--ignore-unfixed` | Bỏ qua CVE chưa có patch — tránh false positive |
| `--exit-code 1` | Fail pipeline, block merge |
| `.trivyignore` | Exception có lý do, có thời hạn |
| Scan cả `os` + `library` | OS packages + language packages |
| SARIF → GitHub Security | Centralized vulnerability dashboard |
| Schedule scan | Scan images trong registry định kỳ (new CVEs) |
| Pin base image | `FROM node:20.11.0-alpine3.19` thay vì `node:latest` |

---

## 8. ECR Native Scanning

AWS ECR cũng có built-in scanning (dùng Inspector):

```hcl
# ecr.tf
resource "aws_ecr_repository" "myapp" {
  name = "myapp"
  
  image_scanning_configuration {
    scan_on_push = true          # Scan mỗi khi push
  }
  
  image_tag_mutability = "IMMUTABLE"   # Không cho overwrite tag
}
```

> **ECR scan vs Trivy:** ECR scan chỉ OS packages. Trivy scan cả language packages (npm, pip, go modules). **Dùng cả hai**: ECR scan ở registry, Trivy scan ở CI.
