# W10 — D2: Secrets Rotation + Supply Chain Security

> **Ngày:** T3 16/06/2026 | **Theme:** Secure & Operate
> **Commit prefix:** `[W10-D2]`

---

## 🎯 Mục tiêu học tập

Sau ngày hôm nay, bạn có thể:

- [ ] Cấu hình AWS Secrets Manager với rotation schedule
- [ ] Deploy External Secrets Operator (ESO) và sync secrets từ AWS vào K8s
- [ ] Tích hợp Trivy image scan trong CI pipeline (fail on HIGH/CRITICAL)
- [ ] Ký image với Cosign — cả keyless OIDC và key-based
- [ ] Cấu hình admission webhook để verify signature trước khi deploy
- [ ] Viết exception policy cho CVE cụ thể (có thời hạn)

---

## 📚 Kiến thức trọng tâm

### Tổng quan — 2 trụ cột Security

```
┌───────────────────────────────────────────────────────────┐
│                  W10-D2 Security Focus                     │
│                                                            │
│  ┌──────────────────────┐   ┌────────────────────────┐    │
│  │  SECRETS MANAGEMENT  │   │  SUPPLY CHAIN SECURITY │    │
│  │                      │   │                        │    │
│  │  "Credentials phải   │   │  "Image deploy lên     │    │
│  │   xoay tự động,      │   │   cluster phải verified│    │
│  │   dev không touch"    │   │   — không trust blind" │    │
│  │                      │   │                        │    │
│  │  ┌────────────────┐  │   │  ┌──────────────────┐  │    │
│  │  │ AWS Secrets    │  │   │  │ Trivy Scan       │  │    │
│  │  │ Manager        │──│──►│  │ (CI pipeline)    │  │    │
│  │  └────────┬───────┘  │   │  └──────────────────┘  │    │
│  │           │          │   │                        │    │
│  │  ┌────────▼───────┐  │   │  ┌──────────────────┐  │    │
│  │  │ External       │  │   │  │ Cosign Sign      │  │    │
│  │  │ Secrets Op.    │  │   │  │ (CI pipeline)    │  │    │
│  │  └────────┬───────┘  │   │  └──────────────────┘  │    │
│  │           │          │   │                        │    │
│  │  ┌────────▼───────┐  │   │  ┌──────────────────┐  │    │
│  │  │ K8s Secret     │  │   │  │ Admission Verify │  │    │
│  │  │ (auto-sync)    │  │   │  │ (cluster gate)   │  │    │
│  │  └────────────────┘  │   │  └──────────────────┘  │    │
│  └──────────────────────┘   └────────────────────────┘    │
└───────────────────────────────────────────────────────────┘
```

### Chi tiết từng topic

| # | File kiến thức | Nội dung |
|---|---|---|
| 1 | [01-aws-secrets-manager.md](knowledge/01-aws-secrets-manager.md) | Secrets Manager architecture, rotation, IAM policy, pricing |
| 2 | [02-external-secrets-operator.md](knowledge/02-external-secrets-operator.md) | ESO install, SecretStore, ExternalSecret CRD, refreshInterval, zero-restart sync |
| 3 | [03-trivy-ci-scan.md](knowledge/03-trivy-ci-scan.md) | Trivy scan modes, CI integration (GitHub Actions/GitLab CI), severity policy, SBOM |
| 4 | [04-cosign-signing.md](knowledge/04-cosign-signing.md) | Cosign keyless OIDC, key-based signing, verify, Sigstore/Rekor transparency log |
| 5 | [05-admission-verify-signature.md](knowledge/05-admission-verify-signature.md) | Kyverno/Connaisseur verify image, policy config, exception handling |
| 6 | [06-cve-exception-policy.md](knowledge/06-cve-exception-policy.md) | Exception ADR, .trivyignore, time-bound exceptions, risk acceptance |

---

## 🔗 Tài liệu tham khảo

| Tài liệu | Link | Ưu tiên |
|---|---|---|
| AWS Secrets Manager | https://docs.aws.amazon.com/secretsmanager | ⭐⭐⭐ Đọc trước |
| External Secrets Operator | https://external-secrets.io/latest | ⭐⭐⭐ Quan trọng |
| Trivy Documentation | https://aquasecurity.github.io/trivy | ⭐⭐⭐ Thực hành |
| Cosign / Sigstore | https://docs.sigstore.dev/cosign/overview | ⭐⭐⭐ Quan trọng |
| SLSA Framework | https://slsa.dev | ⭐⭐ Cần biết |
| Kyverno Verify Images | https://kyverno.io/docs/writing-policies/verify-images | ⭐⭐ Thực hành |

---

## 🏗️ Cấu trúc thư mục thực hành

```
cloud/w10/day2/
├── day-02.md                         # File này
├── knowledge/
│   ├── 01-aws-secrets-manager.md
│   ├── 02-external-secrets-operator.md
│   ├── 03-trivy-ci-scan.md
│   ├── 04-cosign-signing.md
│   ├── 05-admission-verify-signature.md
│   └── 06-cve-exception-policy.md
├── eso/
│   ├── secret-store.yaml
│   ├── external-secret-db.yaml
│   └── external-secret-api-key.yaml
├── signing/
│   ├── cosign-keypair/
│   │   └── README.md
│   └── verify-policy.yaml
└── ci-trivy/
    ├── .github/
    │   └── workflows/
    │       └── scan-and-sign.yaml
    └── .trivyignore
```

---

## ✅ Checklist tự kiểm tra

- [ ] Tạo secret trong AWS Secrets Manager bằng CLI/Terraform
- [ ] Enable automatic rotation 30 ngày
- [ ] Deploy ESO và tạo SecretStore kết nối AWS
- [ ] Tạo ExternalSecret với `refreshInterval: 1m` — verify secret tự sync
- [ ] Chạy `trivy image scan` locally — hiểu output severity levels
- [ ] Viết GitHub Actions workflow: build → scan → fail nếu HIGH/CRITICAL
- [ ] Ký image với Cosign keyless (GitHub Actions OIDC)
- [ ] Verify signature: `cosign verify --certificate-identity --certificate-oidc-issuer`
- [ ] Deploy Kyverno policy verify signature — test với unsigned image
- [ ] Viết .trivyignore cho 1 CVE cụ thể với comment giải thích

---

## 📝 Ghi chú cá nhân

<!-- Ghi lại những điểm khó hiểu, câu hỏi cần hỏi mentor -->

**Câu hỏi / Vướng mắc:**

**Điểm đã hiểu rõ:**

**Kế hoạch thực hành:**
