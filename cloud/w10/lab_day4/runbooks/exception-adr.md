# Exception ADR: CVE Without Available Patch

**ADR-001** | Status: ACTIVE | Created: 2026-06-18

---

## Context

Khi CI pipeline phát hiện CVE mức **HIGH** hoặc **CRITICAL** nhưng chưa có patch từ upstream, team cần có quy trình documented để tạm thời exempt CVE đó trong khi chờ fix.

---

## Template: Ghi lại Exception

> Sao chép section này cho mỗi CVE exception

### CVE-XXXX-XXXXX

| Field         | Value |
|---------------|-------|
| **CVE ID**    | CVE-XXXX-XXXXX |
| **Severity**  | HIGH / CRITICAL |
| **Package**   | package-name@version |
| **Component** | Image: `ghcr.io/nhatphanhk/w10-api` |
| **Discovered**| YYYY-MM-DD |
| **Fix ETA**   | YYYY-MM-DD (hoặc "Pending upstream") |
| **Owner**     | @github-username |

#### Lý do exception

Mô tả tại sao không thể fix ngay:
- Upstream chưa release patch
- Dependency không có version tương thích
- Fix yêu cầu major version bump ảnh hưởng production

#### Risk Assessment

| Risk Factor   | Assessment |
|---------------|------------|
| **Exploitability** | Remote/Local/Network |
| **Attack Vector** | Internet-facing / Internal only |
| **Data Exposure**  | PII / None |
| **Mitigations**    | Network policy, WAF rule, etc. |

**Risk Level**: LOW / MEDIUM / HIGH (sau khi xem xét mitigations)

#### Action Plan

- [ ] Monitor upstream advisory
- [ ] Apply network policy để giảm attack surface
- [ ] Update dependency khi patch available
- [ ] Re-scan sau patch: YYYY-MM-DD

#### Trivy Ignore Config

Tạo file `.trivyignore` tại root để skip CVE đã được document:

```
# CVE-XXXX-XXXXX - Xem ADR: exception-adr.md
# Fix ETA: YYYY-MM-DD | Owner: @username
CVE-XXXX-XXXXX
```

---

## Quy trình Approval

```
DevOps Engineer phát hiện CVE
        │
        ▼
   Có patch available?
   ├── YES → Fix ngay, không cần ADR
   └── NO  ↓
        │
        ▼
   Điền exception template ở trên
        │
        ▼
   Tech Lead review + approve
        │
        ▼
   Thêm vào .trivyignore với comment
        │
        ▼
   Set reminder fix theo Fix ETA
```

---

## Quy định

1. **Mỗi exception phải được approve** bởi ít nhất 1 Tech Lead
2. **Thời hạn tối đa**: 90 ngày (sau đó bắt buộc fix hoặc review lại)
3. **Không được exception CRITICAL** nếu service internet-facing và không có mitigation
4. **Review định kỳ**: Mỗi sprint retrospective phải review danh sách exceptions

---

## Exceptions Hiện Tại

| CVE ID | Package | Severity | Fix ETA | Status |
|--------|---------|----------|---------|--------|
| (none) | -       | -        | -       | -      |

> Khi có exception thực, cập nhật bảng này.

---

## Tham khảo

- [Trivy docs - Vulnerability Filtering](https://aquasecurity.github.io/trivy/latest/docs/configuration/filtering/)
- [NVD - National Vulnerability Database](https://nvd.nist.gov/)
- [GitHub Security Advisories](https://github.com/advisories)
