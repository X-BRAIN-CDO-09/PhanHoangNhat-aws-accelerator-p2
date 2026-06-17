# W10 — D2: AWS Security — IAM, GuardDuty & CloudTrail

> **Ngày:** T3 17/06/2026 | **Theme:** Operate Confidently on AWS
> **Commit prefix:** `[W10-D2]`

---

## 🎯 Mục tiêu học tập

Sau ngày hôm nay, bạn có thể:

- [ ] Viết IAM Policy đúng với Least Privilege
- [ ] Dùng IAM Role thay IAM User cho EC2/Lambda
- [ ] Bật GuardDuty + nhận alert khi có threat
- [ ] Query CloudTrail để audit ai đã làm gì
- [ ] Enable Security Hub để aggregate findings

---

## 📚 Kiến thức trọng tâm

### Security Layering Model

```
IAM (Who can do what)
  ↓
CloudTrail (What was done & when)
  ↓
GuardDuty (Detect threats in real-time)
  ↓
Security Hub (Aggregate all findings)
  ↓
AWS Config (Continuous compliance check)
```

### Chi tiết từng topic

| # | File kiến thức | Nội dung |
|---|---|---|
| 1 | [01-iam-deep-dive.md](knowledge/01-iam-deep-dive.md) | IAM Policy, Least Privilege, Role vs User, Instance Profile |
| 2 | [02-cloudtrail.md](knowledge/02-cloudtrail.md) | Audit trail, Management/Data Events, Athena query |
| 3 | [03-guardduty.md](knowledge/03-guardduty.md) | Threat detection, Finding types, Alert integration |
| 4 | [04-security-hub.md](knowledge/04-security-hub.md) | Aggregate findings, CIS Benchmark, compliance |
| 5 | [05-security-best-practices.md](knowledge/05-security-best-practices.md) | Security checklist, layering model, production hardening |

---

## 🔗 Tài liệu tham khảo

| Tài liệu | Link | Ưu tiên |
|---|---|---|
| IAM Best Practices | https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html | ⭐⭐⭐ Đọc trước |
| CloudTrail User Guide | https://docs.aws.amazon.com/awscloudtrail/latest/userguide/cloudtrail-user-guide.html | ⭐⭐⭐ Quan trọng |
| GuardDuty User Guide | https://docs.aws.amazon.com/guardduty/latest/ug/what-is-guardduty.html | ⭐⭐ Cần biết |
| Security Hub User Guide | https://docs.aws.amazon.com/securityhub/latest/userguide/what-is-securityhub.html | ⭐⭐ Cần biết |
| AWS Security Best Practices | https://docs.aws.amazon.com/prescriptive-guidance/latest/aws-startup-security-baseline | ⭐ Nâng cao |

---

## 🏗️ Cấu trúc thư mục thực hành

```
cloud/w10/day2/
├── day-02.md                      # File này
├── knowledge/
│   ├── 01-iam-deep-dive.md
│   ├── 02-cloudtrail.md
│   ├── 03-guardduty.md
│   ├── 04-security-hub.md
│   └── 05-security-best-practices.md
└── terraform/
    ├── iam.tf
    ├── cloudtrail.tf
    ├── guardduty.tf
    ├── security-hub.tf
    └── variables.tf
```

---

## ✅ Checklist tự kiểm tra

- [ ] Viết IAM Policy với đúng Effect/Action/Resource/Condition
- [ ] Giải thích Least Privilege principle và áp dụng vào policy
- [ ] Phân biệt IAM User vs IAM Role — khi nào dùng gì
- [ ] Tạo IAM Role cho EC2 (Instance Profile) bằng Terraform
- [ ] Bật CloudTrail và query log: ai đã xoá S3 bucket?
- [ ] Bật GuardDuty và hiểu các Finding types
- [ ] Enable Security Hub và xem compliance score
- [ ] Vẽ Security Layering diagram cho production AWS account

---

## 📝 Ghi chú cá nhân

<!-- Ghi lại những điểm khó hiểu, câu hỏi cần hỏi mentor -->

**Câu hỏi / Vướng mắc:**

**Điểm đã hiểu rõ:**

**Kế hoạch thực hành:**
