# EC2 Pricing Models — On-Demand, Savings Plans, Reserved, Spot

> **Nguồn:** W10-D3 | **Chủ đề:** AWS Pricing Models

---

## 1. Tổng quan 4 Pricing Models

```
┌──────────────────────────────────────────────────────────────┐
│                   EC2 Pricing Models                         │
│                                                              │
│  ┌──────────────┐  Linh hoạt nhất, đắt nhất                │
│  │  On-Demand   │  Pay-as-you-go, không commitment          │
│  └──────────────┘                                            │
│        ↓ Giảm 40-60%                                        │
│  ┌──────────────┐  Commit $/hour, linh hoạt instance type   │
│  │ Savings Plans│  1 hoặc 3 năm                             │
│  └──────────────┘                                            │
│        ↓ Giảm 40-72%                                        │
│  ┌──────────────┐  Commit instance type cụ thể              │
│  │  Reserved    │  1 hoặc 3 năm                             │
│  └──────────────┘                                            │
│        ↓ Giảm 70-90%                                        │
│  ┌──────────────┐  Dùng capacity dư, có thể bị interrupt    │
│  │    Spot      │  Không commitment, không guarantee         │
│  └──────────────┘                                            │
└──────────────────────────────────────────────────────────────┘
```

---

## 2. So sánh chi tiết

| Tiêu chí | On-Demand | Savings Plans | Reserved | Spot |
|---|---|---|---|---|
| **Discount** | 0% (baseline) | 40-60% | 40-72% | 70-90% |
| **Commitment** | Không | $/hour, 1-3 năm | Instance type, 1-3 năm | Không |
| **Flexibility** | Rất cao | Cao | Thấp | Cao (nhưng bị interrupt) |
| **Availability** | Guaranteed | Guaranteed | Guaranteed | Không guaranteed |
| **Payment** | Per-second/hour | All/Partial/No upfront | All/Partial/No upfront | Per-second |
| **Cancel** | Bất kỳ lúc nào | Không | Không (có marketplace) | Bất kỳ lúc nào |

---

## 3. On-Demand

**Dùng khi:** Workload không dự đoán được, testing, dev environment.

```
Chi phí ví dụ (ap-southeast-1):
  t3.micro:   $0.0104/hour  ≈ $7.5/month
  t3.medium:  $0.0416/hour  ≈ $30/month
  m5.xlarge:  $0.192/hour   ≈ $138/month
  c5.2xlarge: $0.340/hour   ≈ $245/month
```

### Khi nào dùng:

```
✅ Spiky workloads (không dự đoán được)
✅ Short-term workloads (vài giờ/ngày)
✅ Dev/test environments
✅ Applications đang thử nghiệm
❌ Steady-state workloads (nên dùng Savings Plans)
❌ Batch processing (nên dùng Spot)
```

---

## 4. Savings Plans

**Dùng khi:** Workload steady-state, commit $/hour trong 1-3 năm.

### 2 loại Savings Plans:

| Loại | Flexibility | Discount |
|---|---|---|
| **Compute Savings Plans** | Bất kỳ instance family, size, region, OS | Thấp hơn |
| **EC2 Instance Savings Plans** | Cố định instance family + region | Cao hơn |

### Ví dụ tính toán:

```
Scenario: Chạy 2 x m5.xlarge 24/7

On-Demand:
  2 × $0.192/hour × 730 hours = $280.32/month

Compute Savings Plan (1 year, no upfront):
  Commit: $0.242/hour
  Savings: ~40%
  Cost: ≈ $176.66/month

EC2 Instance Savings Plan (1 year, all upfront):
  Savings: ~55%
  Cost: ≈ $126.14/month
```

### Cách chọn:

```
Compute Savings Plans:
  ✅ Muốn flexibility (đổi instance type/region)
  ✅ Dùng cả EC2 + Lambda + Fargate
  ✅ Chưa chắc về architecture tương lai

EC2 Instance Savings Plans:
  ✅ Đã chắc chắn instance family + region
  ✅ Muốn discount cao nhất
  ✅ Workload stable (ít thay đổi)
```

---

## 5. Reserved Instances (RI)

**Dùng khi:** Biết chính xác instance type, chạy 24/7, cam kết 1-3 năm.

### Payment options:

| Option | Upfront | Monthly | Discount |
|---|---|---|---|
| **All Upfront** | Trả hết | $0 | Cao nhất (~60-72%) |
| **Partial Upfront** | Trả 1 phần | Giảm | Trung bình (~50-60%) |
| **No Upfront** | $0 | Giảm nhẹ | Thấp nhất (~40-50%) |

### RI vs Savings Plans:

```
Reserved Instances:
  ✅ Discount có thể cao hơn 1 chút
  ❌ Lock vào instance type + AZ (Standard RI)
  ❌ Không cover Lambda, Fargate
  → Đang dần bị thay thế bởi Savings Plans

Savings Plans:
  ✅ Flexible hơn
  ✅ Cover EC2 + Lambda + Fargate
  ✅ AWS recommend dùng thay RI
  → Nên dùng Savings Plans cho trường hợp mới
```

---

## 6. Spot Instances

**Dùng khi:** Workload có thể bị interrupt, batch processing, CI/CD.

### Cách Spot hoạt động:

```
AWS có capacity dư
    ↓
Bán với giá Spot (70-90% rẻ hơn On-Demand)
    ↓
Khi AWS cần capacity lại
    ↓
Gửi 2-minute warning
    ↓
Terminate Spot instance
```

### Use cases phù hợp:

```
✅ Batch processing (MapReduce, video encoding)
✅ CI/CD build servers
✅ Big data analytics (EMR, Spark)
✅ Machine learning training
✅ Dev/test environments
✅ Containerized workloads (ECS/EKS)

❌ Databases (stateful, không thể interrupt)
❌ Mission-critical production (single instance)
❌ Workloads cần guarantee uptime
```

### Spot Best Practices:

```
1. Diversify instance types (không chỉ 1 loại)
   → m5.xlarge, m5a.xlarge, m5d.xlarge, m4.xlarge

2. Dùng Spot Fleet hoặc ASG mixed instances
   → Tự động chọn pool rẻ nhất

3. Handle Spot interruption:
   → Dùng EC2 metadata để detect 2-min warning
   → Graceful shutdown, save state
   
4. Dùng Spot + On-Demand mix:
   → Base capacity = On-Demand/RI
   → Burst capacity = Spot
```

### Terraform — Spot Instance:

```hcl
resource "aws_instance" "spot_worker" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "m5.xlarge"
  
  instance_market_options {
    market_type = "spot"
    spot_options {
      max_price                      = "0.10"  # Max price/hour
      instance_interruption_behavior = "terminate"
      spot_instance_type             = "one-time"
    }
  }
  
  tags = {
    Name = "spot-worker"
  }
}
```

---

## 7. Decision Tree — Chọn pricing model

```
Workload chạy bao lâu?
  │
  ├── Vài phút/giờ → On-Demand
  │
  ├── 24/7 steady state
  │     │
  │     ├── Biết chính xác instance type → EC2 Instance Savings Plan
  │     │
  │     └── Muốn flexibility → Compute Savings Plan
  │
  ├── Batch/stateless (có thể interrupt)
  │     │
  │     └── → Spot Instances
  │
  └── Mixed workload
        │
        └── Base = Savings Plan + Burst = Spot
```

---

## 🔗 Tài liệu tham khảo

- [AWS Pricing Calculator](https://calculator.aws) ⭐⭐⭐
- [Savings Plans Guide](https://docs.aws.amazon.com/savingsplans/latest/userguide/what-is-savings-plans.html) ⭐⭐⭐
- [Spot Instance Guide](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/using-spot-instances.html) ⭐⭐
