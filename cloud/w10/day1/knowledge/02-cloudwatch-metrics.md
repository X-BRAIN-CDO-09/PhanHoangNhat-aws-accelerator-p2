# CloudWatch Metrics — Thu thập và lưu trữ

> **Nguồn:** W10-D1 | **Chủ đề:** CloudWatch Metrics

---

## 1. Cấu trúc Metric — Namespace và Dimension

Mỗi CloudWatch Metric bao gồm:

```
CloudWatch Metric = Namespace + MetricName + Dimensions + Timestamp + Value + Unit

Ví dụ:
  Namespace:  AWS/EC2
  MetricName: CPUUtilization
  Dimensions: {InstanceId: i-0123456789abcdef0}
  Value:      75.5
  Unit:       Percent
```

| Thành phần | Mô tả | Ví dụ |
|---|---|---|
| **Namespace** | Nhóm logic (thường theo service) | `AWS/EC2`, `AWS/RDS`, `MyApp/Production` |
| **MetricName** | Tên metric cụ thể | `CPUUtilization`, `RequestCount` |
| **Dimensions** | Key-value để filter | `InstanceId`, `LoadBalancer` |
| **Value** | Giá trị số | `75.5` |
| **Unit** | Đơn vị | `Percent`, `Count`, `Seconds`, `Bytes` |

---

## 2. AWS-native metrics (không cần cấu hình)

Các metrics **tự động** được CloudWatch thu thập:

| Service | Key Metrics |
|---|---|
| **EC2** | `CPUUtilization`, `NetworkIn/Out`, `DiskReadOps`, `StatusCheckFailed` |
| **RDS** | `DatabaseConnections`, `FreeStorageSpace`, `ReadLatency`, `WriteLatency` |
| **ELB/ALB** | `RequestCount`, `TargetResponseTime`, `HTTPCode_Target_5XX_Count` |
| **Lambda** | `Invocations`, `Errors`, `Duration`, `Throttles`, `ConcurrentExecutions` |
| **ECS** | `CPUUtilization`, `MemoryUtilization`, `RunningTaskCount` |
| **S3** | `BucketSizeBytes`, `NumberOfObjects`, `AllRequests` (cần enable) |

> **Lưu ý quan trọng:** EC2 **KHÔNG** tự thu thập **Memory** và **Disk usage** — cần dùng CloudWatch Agent (xem file `05-cloudwatch-agent.md`).

---

## 3. Custom Metrics — Gửi từ application

Dùng AWS SDK (boto3) để gửi custom metric:

```python
import boto3

cloudwatch = boto3.client('cloudwatch', region_name='ap-southeast-1')

# Gửi metric đơn
cloudwatch.put_metric_data(
    Namespace='MyApp/Production',
    MetricData=[
        {
            'MetricName': 'OrdersProcessed',
            'Dimensions': [
                {'Name': 'Environment', 'Value': 'production'},
                {'Name': 'Service',     'Value': 'order-service'},
            ],
            'Value': 42,
            'Unit': 'Count'
        },
        {
            'MetricName': 'OrderProcessingTime',
            'Dimensions': [
                {'Name': 'Environment', 'Value': 'production'},
            ],
            'Value': 1.25,
            'Unit': 'Seconds'
        }
    ]
)
```

### Use cases cho Custom Metrics:

```
Business metrics:
  - OrdersProcessed, Revenue, ActiveUsers
  
Application metrics:
  - QueueDepth, CacheHitRate, ErrorCount
  
Infrastructure (custom):
  - MemoryUsage (qua CloudWatch Agent)
  - DiskUsage (qua CloudWatch Agent)
```

---

## 4. Metric Math — Tính toán metric phức tạp

Metric Math cho phép tính toán trên nhiều metrics mà **không cần code**:

```
# Tính Error Rate từ 2 metrics
METRICS("AWS/ApplicationELB", "HTTPCode_Target_5XX_Count") /
METRICS("AWS/ApplicationELB", "RequestCount") * 100

# Tính tổng CPU từ nhiều instance
SUM(SEARCH('{AWS/EC2,InstanceId} MetricName="CPUUtilization"', 'Average', 300))
```

### Các hàm Metric Math phổ biến:

| Hàm | Mô tả | Ví dụ |
|---|---|---|
| `SUM` | Tổng | `SUM(METRICS("m1"))` |
| `AVG` | Trung bình | `AVG(METRICS("m1"))` |
| `MIN/MAX` | Min/Max | `MAX(m1, m2)` |
| `METRICS()` | Lấy metric data | `METRICS("m1")` |
| `SEARCH()` | Tìm metrics theo pattern | `SEARCH('{AWS/EC2}...')` |
| `IF()` | Conditional | `IF(m1 > 100, 1, 0)` |

---

## 5. Metric Resolution

| Loại | Period | Chi phí | Use case |
|---|---|---|---|
| **Standard** | 1 phút (60s) | Miễn phí | Hầu hết workloads |
| **High Resolution** | 1–10 giây | Phí thêm ($0.30/metric/tháng) | Real-time trading, gaming |

> **Best practice:** Dùng Standard resolution (60s) cho hầu hết trường hợp. High Resolution chỉ khi thực sự cần real-time.

---

## 6. Metric Retention

CloudWatch tự động aggregate và lưu trữ metrics theo timeline:

```
Dữ liệu gốc (1s/60s)  → Giữ 15 ngày
Aggregate 5 phút       → Giữ 63 ngày  
Aggregate 1 giờ        → Giữ 455 ngày (≈15 tháng)
```

> Sau 15 ngày, bạn không thể query dữ liệu ở độ phân giải 1 phút nữa — chỉ còn 5 phút hoặc 1 giờ.

---

## 🔗 Tài liệu tham khảo

- [CloudWatch Metrics Concepts](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/cloudwatch_concepts.html) ⭐⭐⭐
- [Publishing Custom Metrics](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/publishingMetrics.html) ⭐⭐
- [Metric Math Syntax](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/using-metric-math.html) ⭐⭐
