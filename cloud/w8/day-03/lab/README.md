# Final Project: Deploy a Web App on AWS 🚀

> **Week 8 · Day 3 Lab** — Terraform Infrastructure as Code

## Mục tiêu

Triển khai một Web Application hoàn chỉnh trên AWS bằng Terraform với kiến trúc:

```
Internet
   │
   ▼
 EC2 (Public Subnet)     ← Web Server (Nginx + PHP)
   │
   ├──► RDS MySQL (Private Subnet)   ← Database
   │
   └──► S3 Bucket                    ← Static Assets

All state → S3 Backend + DynamoDB Locking
```

---

## Kiến trúc chi tiết

```
VPC (10.0.0.0/16)
├── Public Subnet A  (10.0.1.0/24)  ← AZ[0]
│     └── EC2 Web Server (Nginx + PHP-FPM)
├── Public Subnet B  (10.0.2.0/24)  ← AZ[1] (dự phòng / ALB)
├── Private Subnet A (10.0.11.0/24) ← AZ[0]
│     └── RDS MySQL (Primary)
├── Private Subnet B (10.0.12.0/24) ← AZ[1]
│     └── RDS MySQL (Standby - Multi-AZ ready)
├── Internet Gateway  → Public Route Table
└── NAT Gateway       → Private Route Table

Security Groups:
├── EC2 SG : SSH(22) ← your IP | HTTP(80) + HTTPS(443) ← 0.0.0.0/0
└── RDS SG : MySQL(3306) ← EC2 SG only
```

---

## Cấu trúc file

```
lab/
├── providers.tf              # Terraform version + AWS provider + S3 backend
├── variables.tf              # Khai báo tất cả biến đầu vào
├── terraform.tfvars          # Giá trị biến (KHÔNG commit lên git!)
├── terraform.tfvars.example  # Template an toàn để commit
│
├── network.tf                # [Step 1] VPC + Subnets + IGW + NAT Gateway
├── security.tf               # [Step 5] Security Groups (EC2 + RDS)
├── ec2.tf                    # [Step 2] EC2 Web Server + Key Pair
├── rds.tf                    # [Step 3] RDS MySQL + DB Subnet Group
├── s3.tf                     # [Step 4] S3 Bucket + IAM Role/Policy
├── bootstrap.tf              # Tạo S3 backend + DynamoDB table
├── outputs.tf                # Output values sau khi deploy
│
├── templates/
│   └── user_data.sh.tpl      # Bootstrap script cho EC2 (cài Nginx, PHP, etc.)
│
├── generated/                # SSH private key (tự sinh, KHÔNG commit)
│   └── webapp-web-server.pem
│
└── .gitignore
```

---

## Yêu cầu trước khi bắt đầu

| Công cụ | Phiên bản tối thiểu | Cài đặt |
|---------|--------------------|----|
| Terraform | >= 1.5.0 | [terraform.io/downloads](https://developer.hashicorp.com/terraform/downloads) |
| AWS CLI | >= 2.x | [aws.amazon.com/cli](https://aws.amazon.com/cli/) |
| AWS Credentials | IAM User/Role | `aws configure` hoặc environment variables |

**Quyền AWS IAM cần có:**
- EC2: `ec2:*`
- RDS: `rds:*`
- S3: `s3:*`
- IAM: `iam:CreateRole`, `iam:AttachRolePolicy`, `iam:PassRole`
- DynamoDB: `dynamodb:CreateTable`, `dynamodb:GetItem`, `dynamodb:PutItem`, `dynamodb:DeleteItem`

---

## Hướng dẫn từng bước

### Bước 0 — Chuẩn bị môi trường

```bash
# Kiểm tra Terraform đã cài chưa
terraform --version

# Kiểm tra AWS CLI đã cấu hình chưa
aws sts get-caller-identity

# Lấy IP hiện tại của bạn (dùng cho allowed_ssh_cidr)
curl -s ifconfig.me && echo "/32"
```

---

### Bước 1 — Clone và cấu hình biến

```bash
# Di chuyển vào thư mục lab
cd cloud/w8/day-03/lab

# Tạo file terraform.tfvars từ template
cp terraform.tfvars.example terraform.tfvars
```

Mở file `terraform.tfvars` và điền giá trị thực:

```hcl
aws_region   = "ap-southeast-1"    # Region bạn muốn deploy
project_name = "webapp"             # Prefix cho tên tài nguyên

# QUAN TRỌNG: Thay bằng IP thực của bạn
allowed_ssh_cidr = "YOUR_PUBLIC_IP/32"  # VD: "203.0.113.42/32"

# QUAN TRỌNG: Đổi password mặc định
db_password = "YourSecurePassword123!"  # Ít nhất 8 ký tự
```

> ⚠️ **CẢNH BÁO**: Không bao giờ commit `terraform.tfvars` lên git (đã có trong `.gitignore`).

---

### Bước 2 — Bootstrap: Tạo S3 Backend và DynamoDB Table

> Trước khi dùng remote state, bạn cần tạo S3 bucket và DynamoDB table.

**2a. Comment out backend block trong `providers.tf`:**

```hcl
# terraform {
#   backend "s3" {
#     ...
#   }
# }
```

**2b. Khởi tạo Terraform với local state:**

```bash
terraform init
```

**2c. Chỉ tạo backend resources:**

```bash
terraform apply \
  -target=aws_s3_bucket.tfstate \
  -target=aws_s3_bucket_versioning.tfstate \
  -target=aws_s3_bucket_server_side_encryption_configuration.tfstate \
  -target=aws_s3_bucket_public_access_block.tfstate \
  -target=aws_dynamodb_table.tfstate_lock \
  -target=random_id.tfstate_suffix
```

**2d. Lấy tên bucket và table từ output:**

```bash
terraform output tfstate_bucket_name
terraform output tfstate_dynamodb_table
terraform output backend_config_snippet
```

**2e. Cập nhật `providers.tf` backend block** với tên bucket/table vừa tạo:

```hcl
backend "s3" {
  bucket         = "webapp-tfstate-ap-southeast-1-xxxx"  # Thay bằng tên thực
  key            = "w8/day-03/lab/terraform.tfstate"
  region         = "ap-southeast-1"
  dynamodb_table = "webapp-tfstate-lock"                  # Thay bằng tên thực
  encrypt        = true
}
```

**2f. Uncomment backend block và migrate state:**

```bash
terraform init -migrate-state
# Nhập "yes" khi được hỏi
```

✅ Từ bây giờ, Terraform state được lưu trong S3 với DynamoDB locking!

---

### Bước 3 — [Step 1] Tạo VPC và Subnets

> Xem file: `network.tf`

Kiến trúc mạng:
- **VPC** CIDR: `10.0.0.0/16`
- **2 Public Subnets** (EC2): `10.0.1.0/24`, `10.0.2.0/24`
- **2 Private Subnets** (RDS): `10.0.11.0/24`, `10.0.12.0/24`
- **Internet Gateway** → Public Route Table
- **NAT Gateway** → Private Route Table (cho phép private subnet access internet)

```bash
# Xem plan cho networking
terraform plan -target=aws_vpc.main -target=aws_subnet.public -target=aws_subnet.private
```

---

### Bước 4 — Plan toàn bộ infrastructure

```bash
terraform plan
```

Xem kỹ output, đặc biệt chú ý:
- ✅ VPC + 4 subnets + IGW + NAT Gateway
- ✅ 2 Security Groups (EC2 + RDS)
- ✅ EC2 instance trong public subnet
- ✅ RDS MySQL trong private subnet (2 private subnets trong DB Subnet Group)
- ✅ S3 bucket + IAM Role + Instance Profile
- ✅ SSH Key Pair (auto-generated)

---

### Bước 5 — Apply

```bash
terraform apply
```

Nhập `yes` để xác nhận. Quá trình này mất khoảng **10–15 phút** (RDS mất lâu nhất).

**Sau khi hoàn thành, xem output:**

```bash
terraform output
```

Ví dụ output:
```
ec2_public_ip    = "54.123.45.67"
web_url          = "http://54.123.45.67"
rds_endpoint     = "webapp-mysql.xxxx.ap-southeast-1.rds.amazonaws.com:3306"
s3_bucket_name   = "webapp-static-assets-a1b2c3d4"
ssh_command      = "ssh -i generated/webapp-web-server.pem ec2-user@54.123.45.67"
```

---

### Bước 6 — Kiểm tra kết quả

#### 6a. Truy cập web app

```bash
# Lấy URL từ output
terraform output web_url
# Mở browser: http://<ec2_public_ip>
```

Trang web sẽ hiển thị:
- ✅ EC2 instance info (Instance ID, Public IP, AZ)
- ✅ RDS MySQL connection status (Connected / Not Connected)
- ✅ S3 bucket info

#### 6b. SSH vào EC2

```bash
# Chạy lệnh SSH từ output
$(terraform output -raw ssh_command)

# Hoặc thủ công:
ssh -i generated/webapp-web-server.pem ec2-user@$(terraform output -raw ec2_public_ip)
```

#### 6c. Kiểm tra RDS từ EC2

```bash
# SSH vào EC2 trước, sau đó:
mysql -h <rds_hostname> -u admin -p appdb
# Nhập db_password khi được hỏi
```

#### 6d. Kiểm tra S3

```bash
# List objects trong bucket
aws s3 ls s3://$(terraform output -raw s3_bucket_name)/

# Upload file test
echo "<h1>Hello from S3</h1>" | aws s3 cp - s3://$(terraform output -raw s3_bucket_name)/test.html
```

#### 6e. Kiểm tra logs bootstrap trên EC2

```bash
# SSH vào EC2
sudo cat /var/log/user_data.log
sudo systemctl status nginx
sudo systemctl status php-fpm
```

---

### Bước 7 — [Step 5] Xác nhận Security Groups

```bash
# Xem Security Groups đã tạo
aws ec2 describe-security-groups \
  --filters "Name=tag:Project,Values=webapp" \
  --query 'SecurityGroups[*].{Name:GroupName,Rules:IpPermissions}' \
  --output table
```

**Luật bảo mật:**

| Resource | Port | Source | Ghi chú |
|----------|------|--------|---------|
| EC2 | 22 | Your IP (`/32`) | SSH — chỉ IP của bạn |
| EC2 | 80 | `0.0.0.0/0` | HTTP public |
| EC2 | 443 | `0.0.0.0/0` | HTTPS public |
| RDS | 3306 | EC2 Security Group | MySQL — chỉ từ EC2, KHÔNG public |

---

### Bước 8 — Dọn dẹp (Destroy)

> ⚠️ Lệnh này sẽ XÓA tất cả tài nguyên. Dữ liệu sẽ mất!

```bash
terraform destroy
```

Nhập `yes` để xác nhận.

**Sau đó xóa backend resources (nếu muốn):**

```bash
# Xóa objects trong S3 trước (nếu force_destroy=false)
aws s3 rm s3://<tfstate_bucket_name> --recursive

# Xóa bucket và DynamoDB table
aws s3api delete-bucket --bucket <tfstate_bucket_name>
aws dynamodb delete-table --table-name webapp-tfstate-lock
```

---

## Lý giải thiết kế

### Tại sao dùng Private Subnet cho RDS?

RDS MySQL không cần truy cập từ internet. Đặt vào **private subnet** và giới hạn security group chỉ cho phép EC2 kết nối trực tiếp qua cổng 3306 — điều này ngăn chặn tấn công từ bên ngoài.

### Tại sao cần 2 Private Subnets cho RDS?

AWS **bắt buộc** DB Subnet Group phải có ít nhất 2 subnets trong 2 AZ khác nhau. Điều này cũng cho phép bật **Multi-AZ** khi cần độ sẵn sàng cao.

### Tại sao dùng NAT Gateway?

Private subnets không có đường ra internet trực tiếp. NAT Gateway cho phép EC2/RDS trong private subnet **gọi ra internet** (cài updates, gọi AWS APIs) mà không expose public IP.

### Tại sao S3 không public?

Static assets được serve qua EC2 (presigned URLs) hoặc CloudFront — không cần public bucket. Block All Public Access là best practice về bảo mật.

### Tại sao dùng S3 + DynamoDB cho state?

| Feature | Local State | S3 + DynamoDB |
|---------|------------|---------------|
| Chia sẻ team | ❌ | ✅ |
| Locking | ❌ | ✅ (DynamoDB) |
| Versioning | ❌ | ✅ |
| Backup | ❌ | ✅ |
| Mã hóa | ❌ | ✅ |

---

## Xử lý lỗi thường gặp

### Lỗi: `Error: creating DB Subnet Group: DBSubnetGroupDoesNotCoverEnoughAZs`

**Nguyên nhân**: Region chỉ có 1 AZ available, nhưng RDS cần ≥ 2.

**Giải pháp**: Đảm bảo `private_subnet_cidrs` có ít nhất 2 phần tử và region có ≥ 2 AZs.

---

### Lỗi: `Error: timeout while waiting for EC2 instance to become ready`

**Nguyên nhân**: `user_data` script đang chạy.

**Giải pháp**: Chờ thêm 3-5 phút, sau đó SSH vào kiểm tra `/var/log/user_data.log`.

---

### Lỗi: `Cannot connect to RDS from web page`

**Kiểm tra**:
1. EC2 và RDS trong cùng VPC
2. RDS Security Group cho phép port 3306 từ EC2 SG
3. `db_host` trong `user_data` đúng với RDS endpoint

```bash
# Kiểm tra kết nối từ EC2
nc -zv <rds_endpoint> 3306
```

---

### Lỗi: `Error acquiring the state lock`

**Nguyên nhân**: Có process Terraform khác đang chạy, hoặc process trước bị crash.

**Giải pháp**:

```bash
# Xem thông tin lock
terraform force-unlock <LOCK_ID>
```

---

### Lỗi: `InvalidClientTokenId` hoặc `NoCredentialProviders`

**Giải pháp**: Kiểm tra AWS credentials:

```bash
aws configure list
aws sts get-caller-identity
```

---

## Tài nguyên tham khảo

- [Terraform AWS Provider Docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [AWS VPC Documentation](https://docs.aws.amazon.com/vpc/latest/userguide/)
- [Amazon RDS for MySQL](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/CHAP_MySQL.html)
- [Terraform S3 Backend](https://developer.hashicorp.com/terraform/language/settings/backends/s3)
- [AWS S3 Security Best Practices](https://docs.aws.amazon.com/AmazonS3/latest/userguide/security-best-practices.html)

---

## Chi phí ước tính (ap-southeast-1)

| Tài nguyên | Loại | Chi phí/giờ |
|-----------|------|-------------|
| EC2 | t3.micro | ~$0.0104 |
| RDS MySQL | db.t3.micro | ~$0.025 |
| NAT Gateway | — | ~$0.045 + data |
| S3 | Standard | ~$0.025/GB/month |
| EIP (NAT) | — | ~$0.005 |

> 💡 **Tip**: Nhớ `terraform destroy` sau khi học xong để tránh phát sinh chi phí không cần thiết!

---

*Lab W8 Day 3 — PhanHoangNhat AWS Accelerator P2*
