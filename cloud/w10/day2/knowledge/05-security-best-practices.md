# Security Best Practices — Production Checklist

> **Nguồn:** W10-D2 | **Chủ đề:** AWS Security Best Practices

---

## 1. Security Layering Model

AWS Security hoạt động theo mô hình **nhiều lớp (defense in depth)**:

```
Layer 1: IDENTITY & ACCESS (IAM)
  │  → Ai có thể làm gì?
  │  → Least Privilege, MFA, Role-based
  │
  ▼
Layer 2: DETECTION (CloudTrail)
  │  → Ghi lại mọi hành vi
  │  → Audit trail, compliance
  │
  ▼
Layer 3: THREAT DETECTION (GuardDuty)
  │  → Phát hiện threats real-time
  │  → ML-powered anomaly detection
  │
  ▼
Layer 4: AGGREGATION (Security Hub)
  │  → Tổng hợp findings
  │  → Compliance scoring
  │
  ▼
Layer 5: COMPLIANCE (AWS Config)
  │  → Continuous compliance check
  │  → Auto-remediation rules
  │
  ▼
Layer 6: NETWORK (VPC, WAF, Shield)
     → Network isolation
     → Web application firewall
     → DDoS protection
```

### Mỗi layer giải quyết câu hỏi khác nhau:

| Layer | Service | Câu hỏi | Loại |
|---|---|---|---|
| Identity | IAM | Ai có quyền gì? | **Preventive** |
| Detection | CloudTrail | Ai đã làm gì? | **Detective** |
| Threats | GuardDuty | Có ai đang tấn công? | **Detective** |
| Aggregate | Security Hub | Tổng thể security thế nào? | **Detective** |
| Compliance | AWS Config | Resources có compliant không? | **Detective + Corrective** |
| Network | VPC/WAF/Shield | Network có được bảo vệ? | **Preventive** |

---

## 2. Production Security Checklist

### 🔐 IAM

```
✅ Root account:
   - [ ] MFA enabled (hardware key preferred)
   - [ ] No access keys
   - [ ] Email alias (không dùng personal email)
   - [ ] Password policy: 14+ chars, complexity, rotation 90 days

✅ Users & Roles:
   - [ ] Dùng IAM Role cho services (KHÔNG IAM User)
   - [ ] Enforce MFA cho tất cả IAM Users
   - [ ] No inline policies — dùng managed policies
   - [ ] Review permissions quarterly (remove unused)
   - [ ] Implement tag-based access control

✅ Access Keys:
   - [ ] Rotate access keys mỗi 90 ngày
   - [ ] Disable unused access keys
   - [ ] Không commit access keys vào git!
```

### 📋 Logging & Monitoring

```
✅ CloudTrail:
   - [ ] Multi-region trail enabled
   - [ ] Log file validation enabled
   - [ ] S3 bucket encrypted (KMS)
   - [ ] S3 bucket access restricted
   - [ ] Logs sent to CloudWatch Logs

✅ CloudWatch Alarms cho security events:
   - [ ] Root account usage
   - [ ] IAM policy changes
   - [ ] Security group changes
   - [ ] NACL changes
   - [ ] Console sign-in without MFA
   - [ ] Failed console logins
   - [ ] S3 bucket policy changes
   - [ ] AWS Config changes
```

### 🛡️ Threat Detection

```
✅ GuardDuty:
   - [ ] Enabled in all regions
   - [ ] S3 protection enabled
   - [ ] EKS audit log monitoring enabled
   - [ ] Alert integration (SNS/Slack) cho High+ severity

✅ Security Hub:
   - [ ] Enabled
   - [ ] CIS Benchmark enabled
   - [ ] AWS FSBP enabled
   - [ ] Security Score > 80%
```

### 🌐 Network

```
✅ VPC:
   - [ ] No default VPC in use
   - [ ] Private subnets cho databases, app servers
   - [ ] NAT Gateway cho outbound (không public IP)
   - [ ] VPC Flow Logs enabled

✅ Security Groups:
   - [ ] No 0.0.0.0/0 cho SSH (port 22)
   - [ ] No 0.0.0.0/0 cho RDP (port 3389)
   - [ ] Principle: deny all, allow specific
   - [ ] Tag all security groups

✅ WAF (nếu có web app):
   - [ ] AWS Managed Rules enabled
   - [ ] Rate limiting configured
   - [ ] IP reputation list
```

### 💾 Data Protection

```
✅ Encryption at rest:
   - [ ] S3: SSE-S3 hoặc SSE-KMS
   - [ ] RDS: Encryption enabled
   - [ ] EBS: Default encryption enabled
   - [ ] DynamoDB: Encryption enabled

✅ Encryption in transit:
   - [ ] HTTPS everywhere (ACM certificates)
   - [ ] TLS 1.2+ only
   - [ ] SSL termination at ALB

✅ S3:
   - [ ] Block Public Access (account level)
   - [ ] Versioning enabled
   - [ ] Access logging enabled
   - [ ] Object Lock for compliance data
```

### 🔑 Secrets Management

```
✅ Secrets:
   - [ ] Dùng AWS Secrets Manager (KHÔNG hardcode)
   - [ ] Auto-rotation enabled
   - [ ] KMS encryption cho secrets
   - [ ] No secrets in environment variables
   - [ ] No secrets in git (.gitignore)
```

---

## 3. Incident Response Playbook

### Bước xử lý khi có security incident:

```
┌──────────────────────────────────────────────────────┐
│  1. DETECT                                            │
│     GuardDuty Finding / Security Hub Alert            │
│     CloudWatch Alarm / Manual report                  │
├──────────────────────────────────────────────────────┤
│  2. ASSESS                                            │
│     Severity? Scope? What's affected?                 │
│     Check CloudTrail: timeline of events              │
├──────────────────────────────────────────────────────┤
│  3. CONTAIN                                           │
│     Isolate affected resources:                       │
│     • EC2: Change SG to deny all                     │
│     • IAM: Disable user/access key                   │
│     • Network: Block IP via NACL/WAF                 │
├──────────────────────────────────────────────────────┤
│  4. ERADICATE                                         │
│     Remove threat:                                    │
│     • Terminate compromised EC2 (snapshot first)     │
│     • Rotate ALL credentials                         │
│     • Patch vulnerabilities                          │
├──────────────────────────────────────────────────────┤
│  5. RECOVER                                           │
│     Restore from clean backup                         │
│     Verify no backdoors remain                        │
│     Monitor closely for recurrence                    │
├──────────────────────────────────────────────────────┤
│  6. POST-MORTEM                                       │
│     Root cause analysis                               │
│     Update runbooks & detection rules                 │
│     Implement preventive measures                     │
└──────────────────────────────────────────────────────┘
```

---

## 4. Quick Reference — Security Commands

```bash
# Check root account MFA
aws iam get-account-summary | grep MFA

# List users without MFA
aws iam generate-credential-report
aws iam get-credential-report --output text --query 'Content' | base64 -d | grep -v "true"

# Find public S3 buckets
aws s3api list-buckets --query 'Buckets[].Name' | \
  xargs -I {} aws s3api get-public-access-block --bucket {}

# Check CloudTrail status
aws cloudtrail get-trail-status --name main-trail

# List GuardDuty findings
aws guardduty list-findings --detector-id <detector-id> \
  --finding-criteria '{"Criterion":{"severity":{"Gte":7}}}'

# Security Hub compliance status
aws securityhub get-findings \
  --filters '{"ComplianceStatus":[{"Value":"FAILED","Comparison":"EQUALS"}]}'
```

---

## 🔗 Tài liệu tham khảo

- [AWS Security Best Practices](https://docs.aws.amazon.com/prescriptive-guidance/latest/aws-startup-security-baseline) ⭐⭐⭐
- [AWS Well-Architected — Security Pillar](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/welcome.html) ⭐⭐⭐
- [CIS AWS Foundations Benchmark](https://www.cisecurity.org/benchmark/amazon_web_services) ⭐⭐
