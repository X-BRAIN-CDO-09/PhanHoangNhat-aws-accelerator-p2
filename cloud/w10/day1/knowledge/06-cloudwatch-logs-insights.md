# CloudWatch Logs Insights — Query và Debug

> **Nguồn:** W10-D1 | **Chủ đề:** CloudWatch Logs Insights

---

## 1. Logs Insights là gì?

**CloudWatch Logs Insights** cho phép query log bằng **SQL-like syntax** — tương tự LogQL (Grafana Loki) hoặc Kibana Query.

### Đặc điểm:

- Query trên **Log Groups** (không phải metrics)
- Trả kết quả trong **vài giây** (dù log hàng GB)
- Hỗ trợ **aggregation**, **filtering**, **parsing**
- Tích hợp sẵn trong CloudWatch Console
- **Pay-per-query** (theo lượng data scan)

---

## 2. Cú pháp cơ bản

### Các commands chính:

| Command | Mô tả | Ví dụ |
|---|---|---|
| `fields` | Chọn fields để hiển thị | `fields @timestamp, @message` |
| `filter` | Lọc log theo điều kiện | `filter @message like /ERROR/` |
| `sort` | Sắp xếp kết quả | `sort @timestamp desc` |
| `limit` | Giới hạn số kết quả | `limit 100` |
| `parse` | Extract field từ message | `parse @message "* - *" as ip, path` |
| `stats` | Aggregation | `stats count(*) by status_code` |
| `display` | Chỉ hiển thị fields cụ thể | `display @timestamp, error_type` |

### Các fields tự động:

| Field | Mô tả |
|---|---|
| `@timestamp` | Thời gian log entry |
| `@message` | Nội dung log (full text) |
| `@logStream` | Tên log stream |
| `@log` | Log group ARN |
| `@ingestionTime` | Thời điểm CloudWatch nhận log |

---

## 3. Các query ví dụ thực tế

### Tìm ERROR logs

```sql
-- Tìm tất cả ERROR logs trong 1 giờ qua
fields @timestamp, @message, @logStream
| filter @message like /ERROR/
| sort @timestamp desc
| limit 100
```

### Đếm error theo loại

```sql
-- Đếm error theo loại
fields @message
| filter @message like /ERROR/
| parse @message "ERROR: * -" as error_type
| stats count(*) as error_count by error_type
| sort error_count desc
```

### Tính p99 latency (JSON log)

```sql
-- Tính p99 latency từ log có format JSON
fields @timestamp, response_time
| filter ispresent(response_time)
| stats pct(response_time, 99) as p99_latency,
        avg(response_time) as avg_latency,
        count(*) as request_count
  by bin(5m)
```

### Top 10 slow requests

```sql
-- Top 10 slow requests
fields @timestamp, @message, response_time, path
| filter response_time > 1000
| sort response_time desc
| limit 10
```

### Error rate theo endpoint

```sql
-- Error rate theo endpoint
fields path, status_code
| filter status_code >= 500
| stats count(*) as errors by path
| sort errors desc
```

### Tìm IP đáng ngờ (security use case)

```sql
-- Top source IPs với nhiều request nhất
fields source_ip
| stats count(*) as request_count by source_ip
| sort request_count desc
| limit 20
```

### Tìm user actions (audit)

```sql
-- Ai đã login thất bại?
fields @timestamp, user_id, action, status
| filter action = "LOGIN" and status = "FAILED"
| stats count(*) as failed_attempts by user_id
| sort failed_attempts desc
```

---

## 4. Parse — Extract structured data từ unstructured log

### Parse với pattern

```sql
-- Log format: "2024-01-15 10:30:00 ERROR [order-service] Order 12345 failed: timeout"
parse @message "* * * [*] Order * failed: *" as date, time, level, service, order_id, reason
| filter level = "ERROR"
| stats count(*) by service, reason
```

### Parse với regex

```sql
-- Extract IP từ log
parse @message /(?<source_ip>\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/
| stats count(*) by source_ip
| sort count(*) desc
```

---

## 5. Stats Functions

| Function | Mô tả | Ví dụ |
|---|---|---|
| `count(*)` | Đếm | `stats count(*)` |
| `sum(field)` | Tổng | `stats sum(bytes)` |
| `avg(field)` | Trung bình | `stats avg(response_time)` |
| `min/max(field)` | Min/Max | `stats max(duration)` |
| `pct(field, N)` | Percentile | `stats pct(latency, 99)` |
| `earliest/latest(field)` | Giá trị đầu/cuối | `stats earliest(@timestamp)` |

### Binning (group by time)

```sql
-- Request count theo 5 phút
stats count(*) as requests by bin(5m)

-- Error rate theo giờ
stats count(*) as errors by bin(1h)
```

---

## 6. Tips & Best Practices

```
✅ Luôn thêm `limit` để tránh scan quá nhiều data (tiết kiệm chi phí)
✅ Dùng `filter` sớm nhất có thể để giảm data scan
✅ Save query thường dùng (CloudWatch Console → Saved Queries)
✅ Dùng `bin()` cho time-series analysis
❌ Tránh query trên time range quá lớn (hàng tháng)
❌ Tránh `like /*/` (regex match all) — quá chậm
```

---

## 🔗 Tài liệu tham khảo

- [CloudWatch Logs Insights Syntax](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax.html) ⭐⭐⭐
- [Sample Queries](https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/CWL_QuerySyntax-examples.html) ⭐⭐
