# W10 — D3: AWS Cost Optimization & Auto Scaling

> **Ngày:** T4 18/06/2026 | **Theme:** Operate Confidently on AWS
> **Commit prefix:** `[W10-D3]`

---

## 🎯 Mục tiêu học tập

Sau ngày hôm nay, bạn có thể:

- [ ] Phân biệt On-Demand / Savings Plans / Reserved / Spot
- [ ] Cấu hình EC2 ASG với Target Tracking Policy
- [ ] Thiết lập AWS Budget với alert 80% và 100%
- [ ] Áp dụng S3 Lifecycle để tối ưu storage cost

---

## 📚 Kiến thức trọng tâm

### Cost Optimization Pyramid

```
Cost Optimization Pyramid:
  Delete unused resources        ← Miễn phí
  Rightsize (Compute Optimizer)  ← Giảm 30-50%
  Savings Plans                  ← Giảm 40-60%
  Spot for batch workloads       ← Giảm 70-90%
  Auto Scaling (không over-provision) ← Giảm 20-40%
```

### Chi tiết từng topic

| # | File kiến thức | Nội dung |
|---|---|---|
| 1 | [01-pricing-models.md](knowledge/01-pricing-models.md) | On-Demand, Savings Plans, Reserved, Spot — so sánh chi tiết |
| 2 | [02-auto-scaling.md](knowledge/02-auto-scaling.md) | EC2 ASG, Launch Template, Scaling Policies, Terraform |
| 3 | [03-budget-cost-explorer.md](knowledge/03-budget-cost-explorer.md) | AWS Budgets, Cost Explorer, Cost Allocation Tags |
| 4 | [04-storage-optimization.md](knowledge/04-storage-optimization.md) | S3 Storage Classes, Lifecycle Rules, EBS optimization |

---

## 🔗 Tài liệu tham khảo

| Tài liệu | Link | Ưu tiên |
|---|---|---|
| AWS Pricing Calculator | https://calculator.aws | ⭐⭐⭐ Thực hành |
| EC2 Auto Scaling Guide | https://docs.aws.amazon.com/autoscaling/ec2/userguide | ⭐⭐⭐ Quan trọng |
| AWS Cost Management Guide | https://docs.aws.amazon.com/cost-management/latest/userguide | ⭐⭐ Cần biết |
| S3 Storage Classes | https://aws.amazon.com/s3/storage-classes | ⭐⭐ Cần biết |
| AWS Well-Architected — Cost Pillar | https://docs.aws.amazon.com/wellarchitected/latest/cost-optimization-pillar | ⭐ Nâng cao |

---

## 🏗️ Cấu trúc thư mục thực hành

```
cloud/w10/day3/
├── day-03.md                      # File này
├── knowledge/
│   ├── 01-pricing-models.md
│   ├── 02-auto-scaling.md
│   ├── 03-budget-cost-explorer.md
│   └── 04-storage-optimization.md
└── terraform/
    ├── asg.tf
    ├── budget.tf
    ├── s3-lifecycle.tf
    └── variables.tf
```

---

## ✅ Checklist tự kiểm tra

- [ ] Phân biệt 4 pricing models và khi nào dùng gì
- [ ] Tính toán savings khi chuyển từ On-Demand sang Savings Plans
- [ ] Tạo EC2 ASG với Target Tracking Policy bằng Terraform
- [ ] Hiểu Cooldown period và tại sao cần nó
- [ ] Thiết lập AWS Budget với alert 80% và 100%
- [ ] Dùng Cost Explorer để phân tích chi phí theo service/tag
- [ ] Cấu hình S3 Lifecycle Rules để chuyển data sang Glacier
- [ ] Hiểu S3 Storage Classes và minimum storage duration

---

## 📝 Ghi chú cá nhân

<!-- Ghi lại những điểm khó hiểu, câu hỏi cần hỏi mentor -->

**Câu hỏi / Vướng mắc:**

**Điểm đã hiểu rõ:**

**Kế hoạch thực hành:**
