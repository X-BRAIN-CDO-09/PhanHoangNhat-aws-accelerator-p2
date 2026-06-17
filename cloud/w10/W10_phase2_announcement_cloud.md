# W10 — Phase 2: Operate Confidently on AWS

> **Tuần:** 16/06/2026 – 20/06/2026
> **Theme:** Operate Confidently on AWS
> **Commit prefix:** `[W10-Dx]`

---

## 📋 Tổng quan tuần 10

Sau 2 tuần nền tảng (W8: Kubernetes Platform) và vận hành thông minh (W9: GitOps + Observability + Progressive Delivery), **W10 tập trung vào vận hành production thực tế trên AWS**: monitoring, security và cost optimization.

```
W8: Build platform (K8s)
W9: Deliver Smartly (GitOps + Observability + Canary)
W10: Operate Confidently (CloudWatch + Security + Cost)
```

---

## 📅 Lịch học

| Ngày | Chủ đề | File |
|---|---|---|
| **D1 — T2 16/06** | AWS CloudWatch: Monitoring, Alarms & SNS | [day1/day-01.md](day1/day-01.md) |
| **D2 — T3 17/06** | AWS Security: IAM, GuardDuty & CloudTrail | [day2/day-02.md](day2/day-02.md) |
| **D3 — T4 18/06** | AWS Cost Optimization & Auto Scaling | [day2/day-03.md](day2/day-03.md) |
| **Lab — T5–T6** | Tích hợp tất cả trên AWS Account | [Lab_homework/](Lab_homework/) |

---

## 🎯 Mục tiêu tuần 10

Sau tuần này, bạn có thể:

### CloudWatch & Alerting (D1)
- [ ] Tạo CloudWatch Alarm với đúng `period`, `evaluation_periods`, `datapoints_to_alarm`
- [ ] Thiết lập SNS → Email + Slack (qua Lambda)
- [ ] Thu thập Memory/Disk từ EC2 bằng CloudWatch Agent
- [ ] Query log với CloudWatch Logs Insights

### Security (D2)
- [ ] Viết IAM Policy đúng với Least Privilege
- [ ] Dùng IAM Role thay IAM User cho EC2/Lambda
- [ ] Bật GuardDuty + nhận alert khi có threat
- [ ] Query CloudTrail để audit ai đã làm gì
- [ ] Enable Security Hub để aggregrate findings

### Cost & Scaling (D3)
- [ ] Phân biệt On-Demand / Savings Plans / Reserved / Spot
- [ ] Cấu hình EC2 ASG với Target Tracking Policy
- [ ] Thiết lập AWS Budget với alert 80% và 100%
- [ ] Áp dụng S3 Lifecycle để tối ưu storage cost

---

## 🧱 Kiến thức nền cần biết trước

- [ ] AWS EC2, S3, IAM cơ bản (Phase 1)
- [ ] Terraform cơ bản (đã làm W8–W9)
- [ ] Kubernetes + GitOps từ W8–W9 (cho context CloudWatch EKS)

---

## 🔑 Key Concepts của tuần

```
CloudWatch Architecture:
  AWS Services → CloudWatch Metrics/Logs
  CloudWatch Alarm → SNS Topic → Email/Lambda/HTTPS

Security Layering:
  IAM (Who can do what)
    ↓
  CloudTrail (What was done & when)
    ↓
  GuardDuty (Detect threats in real-time)
    ↓
  Security Hub (Aggregate all findings)
    ↓
  AWS Config (Continuous compliance check)

Cost Optimization Pyramid:
  Delete unused resources        ← Miễn phí
  Rightsize (Compute Optimizer)  ← Giảm 30-50%
  Savings Plans                  ← Giảm 40-60%
  Spot for batch workloads       ← Giảm 70-90%
  Auto Scaling (không over-provision) ← Giảm 20-40%
```

---

## 📝 Ghi chú cá nhân

**Điểm cần chú ý nhất tuần này:**

**Câu hỏi chuẩn bị hỏi mentor:**

**Kết quả Lab:**
