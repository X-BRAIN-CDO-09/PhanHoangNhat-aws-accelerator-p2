# Cài đặt Terraform

## Phương pháp 1: Sử dụng Package Manager

### Windows

Sử dụng **Chocolatey**, một package manager mã nguồn mở và miễn phí cho Windows:

```bash
choco install terraform
```

## Phương pháp 2: Cài đặt Thủ công

Chọn một trong các bước dưới đây để lấy tệp thực thi:

### Pre-compiled Executable

- Tải xuống file Zip và giải nén
- Terraform chạy trên tệp thực thi tên `terraform`
- Đảm bảo tệp `terraform` khả thi trên **PATH** hệ thống

### Compile from Source

- Clone source code
- Trỏ tới tệp thực thi `terraform`

## Kiểm tra việc cài đặt

Kiểm tra bằng cách mở terminal và hiển thị danh sách **Terraform's available subcommands**:

```bash
terraform -help
```

## Vòng đời Terraform

## Create — Tạo mới hạ tầng

### Tóm tắt những nội dung quan trọng nhất về Terraform Provision AWS EC2

## 1. Mục tiêu

Sử dụng **Terraform** để tạo và quản lý một **EC2 Instance trên AWS** dưới dạng Infrastructure as Code (IaC).

---

## 2. Điều kiện cần có

- Terraform CLI >= 1.2
- AWS CLI
- AWS Account có quyền tạo:
  - EC2 Instance
  - VPC
  - Security Group

- AWS Credentials

---

## 3. Cấu trúc cơ bản của Terraform

Terraform thường gồm:

| Thành phần      | Chức năng                              |
| --------------- | -------------------------------------- |
| terraform block | Khai báo version Terraform và Provider |
| provider block  | Cấu hình nhà cung cấp (AWS)            |
| data block      | Lấy dữ liệu có sẵn từ AWS              |
| resource block  | Tạo tài nguyên mới                     |

---

## 4. File terraform.tf

Khai báo Terraform và AWS Provider:

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }
  }

  required_version = ">= 1.2"
}
```

Ý nghĩa:

- `source`: Provider AWS từ Terraform Registry.
- `version`: Phiên bản AWS Provider.
- `required_version`: Phiên bản Terraform tối thiểu.

---

## 5. File main.tf

### Provider AWS

```hcl
provider "aws" {
  region = "us-west-2"
}
```

Xác định vùng triển khai tài nguyên.

---

### Data Source

Lấy AMI Ubuntu mới nhất:

```hcl
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name = "name"
    values = [
      "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
    ]
  }

  owners = ["099720109477"]
}
```

Lợi ích:

- Không hard-code AMI ID.
- Luôn lấy phiên bản Ubuntu mới nhất.

---

### Resource EC2

```hcl
resource "aws_instance" "app_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"

  tags = {
    Name = "learn-terraform"
  }
}
```

Tạo:

- 1 EC2 Instance
- Loại máy: `t2.micro`
- Sử dụng Ubuntu AMI mới nhất

---

## 6. Cấu hình AWS Credentials

Thiết lập biến môi trường:

```bash
export AWS_ACCESS_KEY_ID=<your_key>
export AWS_SECRET_ACCESS_KEY=<your_secret>
```

Kiểm tra:

```bash
aws configure list
```

---

## 7. Các lệnh Terraform quan trọng

### Format code

```bash
terraform fmt
```

Tự động format file `.tf`.

---

### Khởi tạo project

```bash
terraform init
```

Chức năng:

- Download Provider
- Tạo `.terraform`
- Tạo `.terraform.lock.hcl`

---

### Kiểm tra cấu hình

```bash
terraform validate
```

Kiểm tra:

- Lỗi cú pháp
- Lỗi tham chiếu

---

### Xem kế hoạch triển khai

```bash
terraform plan
```

Cho biết Terraform sẽ:

- Create
- Update
- Destroy

những gì.

---

### Triển khai hạ tầng

```bash
terraform apply
```

Quy trình:

1. Sinh execution plan
2. Hiển thị thay đổi
3. Xác nhận bằng `yes`
4. Tạo EC2 Instance

---

## 8. Terraform State

Sau khi apply:

```bash
terraform.tfstate
```

được tạo ra.

Vai trò:

- Lưu trạng thái thực tế của hạ tầng.
- Terraform dùng file này để:
  - So sánh thay đổi
  - Update tài nguyên
  - Destroy tài nguyên

---

### Xem danh sách tài nguyên trong State

```bash
terraform state list
```

Ví dụ:

```bash
data.aws_ami.ubuntu
aws_instance.app_server
```

---

### Xem chi tiết State

```bash
terraform show
```

---

## 9. Luồng làm việc Terraform chuẩn

```text
Viết cấu hình (.tf)
       ↓
terraform fmt
       ↓
terraform init
       ↓
terraform validate
       ↓
terraform plan
       ↓
terraform apply
       ↓
terraform state
```

---

## 10. Những kiến thức cần nhớ khi học Terraform

# Terraform Basics - Provision AWS EC2

## Mục tiêu

Sử dụng Terraform để tạo và quản lý EC2 Instance trên AWS theo mô hình Infrastructure as Code (IaC).

---

# Điều kiện cần

- Terraform CLI >= 1.2
- AWS CLI
- AWS Account
- AWS Credentials (Access Key, Secret Key)

---

# Cấu trúc Terraform cơ bản

Terraform gồm 4 thành phần chính:

| Thành phần | Mục đích                       |
| ---------- | ------------------------------ |
| terraform  | Khai báo Terraform và Provider |
| provider   | Cấu hình nhà cung cấp (AWS)    |
| data       | Lấy dữ liệu có sẵn             |
| resource   | Tạo tài nguyên mới             |

---

# terraform.tf

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.92"
    }
  }

  required_version = ">= 1.2"
}
```

- Chỉ định AWS Provider.
- Khóa phiên bản Terraform và Provider.

---

# main.tf

## Provider

```hcl
provider "aws" {
  region = "us-west-2"
}
```

Xác định vùng triển khai.

---

## Data Source

```hcl
data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  owners = ["099720109477"]
}
```

Lấy Ubuntu AMI mới nhất từ AWS.

---

## Resource

```hcl
resource "aws_instance" "app_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"

  tags = {
    Name = "learn-terraform"
  }
}
```

Tạo EC2 Instance sử dụng Ubuntu AMI.

---

# Cấu hình AWS Credentials

```bash
export AWS_ACCESS_KEY_ID=<your_access_key>
export AWS_SECRET_ACCESS_KEY=<your_secret_key>
```

Kiểm tra:

```bash
aws configure list
```

---

# Các lệnh Terraform quan trọng

## Format

```bash
terraform fmt
```

Chuẩn hóa định dạng code.

---

## Khởi tạo

```bash
terraform init
```

- Tải Provider
- Tạo `.terraform`
- Tạo `.terraform.lock.hcl`

---

## Kiểm tra cấu hình

```bash
terraform validate
```

Kiểm tra lỗi cú pháp và cấu hình.

---

## Xem kế hoạch

```bash
terraform plan
```

Xem những thay đổi Terraform sẽ thực hiện.

---

## Tạo hạ tầng

```bash
terraform apply
```

Thực thi kế hoạch và tạo tài nguyên trên AWS.

---

# Terraform State

Terraform lưu trạng thái hạ tầng trong:

```text
terraform.tfstate
```

State dùng để:

- Theo dõi tài nguyên
- So sánh thay đổi
- Cập nhật hoặc xóa tài nguyên

---

## Xem tài nguyên trong State

```bash
terraform state list
```

Ví dụ:

```text
data.aws_ami.ubuntu
aws_instance.app_server
```

---

## Xem chi tiết State

```bash
terraform show
```

---

# Workflow Terraform Chuẩn

```text
Write Configuration
        ↓
terraform fmt
        ↓
terraform init
        ↓
terraform validate
        ↓
terraform plan
        ↓
terraform apply
        ↓
terraform state
```

---

# Những kiến thức cần nhớ

1. Provider = AWS, Azure, GCP,...
2. Resource = EC2, S3, VPC,...
3. Data Source = Lấy dữ liệu có sẵn.
4. State File = Nguồn sự thật của Terraform.
5. Luôn chạy `terraform plan` trước `terraform apply`.
6. Không lưu AWS Secret Key trong source code.
7. Không chia sẻ file `terraform.tfstate` nếu chứa dữ liệu nhạy cảm.
8. `terraform init` chỉ cần chạy khi khởi tạo hoặc thay đổi provider/module.

---

# Tóm tắt nhanh

```text
Terraform = Infrastructure as Code

Provider  → Kết nối AWS
Data      → Lấy dữ liệu AWS
Resource  → Tạo tài nguyên AWS
State     → Theo dõi hạ tầng

Lệnh quan trọng:
init → validate → plan → apply
```

## Manage — Quản lí và cập nhật hạ tầng

# Terraform - Variables, Outputs & Modules

## 1. Variables (Biến đầu vào)

### Mục đích

Giúp cấu hình linh hoạt, tránh hard-code giá trị trong code.

### variables.tf

```hcl
variable "instance_name" {
  description = "EC2 Name"
  type        = string
  default     = "learn-terraform"
}

variable "instance_type" {
  description = "EC2 Type"
  type        = string
  default     = "t2.micro"
}
```

### Sử dụng trong Resource

```hcl
resource "aws_instance" "app_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  tags = {
    Name = var.instance_name
  }
}
```

### Override giá trị

```bash
terraform plan -var="instance_type=t2.large"
```

**Lợi ích**

- Dễ tái sử dụng.
- Dễ thay đổi môi trường (dev, test, prod).
- Không cần sửa source code.

---

# 2. Outputs (Biến đầu ra)

### Mục đích

Xuất thông tin từ Terraform để:

- Xem kết quả sau khi deploy.
- Tích hợp với CI/CD.
- Tái sử dụng ở module khác.

### outputs.tf

```hcl
output "instance_hostname" {
  description = "Private DNS"
  value       = aws_instance.app_server.private_dns
}
```

### Xem output

```bash
terraform output
```

Ví dụ:

```text
instance_hostname = "ip-10-0-1-75.us-west-2.compute.internal"
```

---

# 3. Modules

### Mục đích

Module là tập hợp nhiều resource được đóng gói để tái sử dụng.

Tương tự:

```text
Function trong lập trình
=
Module trong Terraform
```

---

## Sử dụng Module VPC

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.19.0"

  name = "example-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-west-2a","us-west-2b","us-west-2c"]
  private_subnets = ["10.0.1.0/24","10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24"]

  enable_dns_hostnames = true
}
```

Module này tự động tạo:

- VPC
- Public Subnet
- Private Subnet
- Route Table
- Internet Gateway
- Security Group

---

## Sử dụng Output từ Module

```hcl
resource "aws_instance" "app_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  vpc_security_group_ids = [
    module.vpc.default_security_group_id
  ]

  subnet_id = module.vpc.private_subnets[0]

  tags = {
    Name = var.instance_name
  }
}
```

---

# 4. Khi thêm Module mới

Luôn chạy:

```bash
terraform init
```

Terraform sẽ:

- Download module.
- Download provider nếu cần.
- Cập nhật workspace.

---

# 5. Terraform Dependency

Terraform tự động xác định thứ tự tạo tài nguyên.

Ví dụ:

```text
VPC
 ↓
Subnet
 ↓
Security Group
 ↓
EC2
```

Không cần khai báo thủ công.

Terraform sử dụng:

```text
Dependency Graph
```

để tính toán thứ tự thực thi.

---

# 6. Terraform State

Xem toàn bộ tài nguyên:

```bash
terraform state list
```

Ví dụ:

```text
aws_instance.app_server
module.vpc.aws_vpc.this[0]
module.vpc.aws_subnet.private[0]
module.vpc.aws_subnet.public[0]
```

Các resource thuộc module sẽ có tiền tố:

```text
module.<module_name>
```

Ví dụ:

```text
module.vpc.aws_vpc.this[0]
```

---

# Những kiến thức cần nhớ

## Variables

```text
var.<variable_name>
```

Dùng để cấu hình linh hoạt.

---

## Outputs

```text
output
terraform output
```

Dùng để lấy dữ liệu sau khi deploy.

---

## Modules

```text
module.<module_name>
```

Dùng để tái sử dụng hạ tầng.

---

## Lệnh quan trọng

```bash
terraform init
terraform plan
terraform apply
terraform output
terraform state list
```

---

# Tóm tắt nhanh

```text
Variables = Input

Outputs = Output

Modules = Reusable Infrastructure

Workflow:

variables.tf
      ↓
main.tf
      ↓
outputs.tf
      ↓
terraform init
      ↓
terraform plan
      ↓
terraform apply
      ↓
terraform output
```

## Destroy — Xóa bỏ hạ tầng

# Terraform - Destroy Infrastructure

## 1. Xóa một Resource

### Bước 1: Xóa resource khỏi cấu hình

Ví dụ comment EC2:

```hcl id="7yudn2"
/*
resource "aws_instance" "app_server" {
  ...
}
*/
```

### Bước 2: Xóa các Output liên quan

Nếu output tham chiếu tới resource đã xóa:

```hcl id="df0qwd"
/*
output "instance_hostname" {
  value = aws_instance.app_server.private_dns
}
*/
```

Nếu không xóa, Terraform sẽ báo lỗi vì tham chiếu không tồn tại.

---

## 2. Áp dụng thay đổi

```bash id="l5q0tq"
terraform apply
```

Terraform sẽ:

```text id="umigj5"
So sánh State hiện tại
↓
Phát hiện resource bị xóa khỏi code
↓
Lập kế hoạch destroy
↓
Xóa resource trên AWS
```

Ví dụ:

```text id="9kzl7u"
Plan: 0 add, 0 change, 1 destroy
```

---

# 3. Xóa toàn bộ Infrastructure

Khi không còn sử dụng môi trường nữa:

```bash id="4mx8pc"
terraform destroy
```

Terraform sẽ:

- Đọc toàn bộ State
- Tạo kế hoạch destroy
- Xóa tất cả resource được quản lý

Ví dụ:

```text id="zdb6ww"
Plan: 0 add, 0 change, 15 destroy
```

---

# 4. Luồng hoạt động của Destroy

```text id="5mhspz"
terraform destroy
        ↓
Read State
        ↓
Create Destroy Plan
        ↓
Confirm (yes)
        ↓
Destroy Resources
        ↓
Update State
```

---

# 5. Terraform State và Destroy

Terraform biết cần xóa gì nhờ:

```text id="wxy8o8"
terraform.tfstate
```

State lưu:

- Resource đã tạo
- Resource ID trên AWS
- Quan hệ phụ thuộc giữa resources

---

# 6. Dependency Graph

Terraform tự động xác định thứ tự xóa.

Ví dụ:

```text id="afll8e"
EC2
 ↑
Subnet
 ↑
VPC
```

Terraform sẽ:

```text id="8mv51h"
Destroy EC2
↓
Destroy Subnet
↓
Destroy VPC
```

Không cần tự quản lý thứ tự.

---

# Lệnh quan trọng

## Xóa một phần hạ tầng

```bash id="jv67fx"
terraform apply
```

(sau khi xóa resource khỏi code)

---

## Xóa toàn bộ hạ tầng

```bash id="k4skpr"
terraform destroy
```

---

## Kiểm tra State

```bash id="a1n5si"
terraform state list
```

---

# Những kiến thức cần nhớ

1. Terraform không xóa resource khi sửa code cho tới khi chạy `apply`.
2. Xóa resource khỏi code + `terraform apply` ⇒ Resource bị destroy.
3. `terraform destroy` ⇒ Xóa toàn bộ infrastructure.
4. Terraform sử dụng `terraform.tfstate` để biết cần xóa gì.
5. Terraform tự xử lý thứ tự destroy bằng Dependency Graph.
6. Luôn kiểm tra execution plan trước khi xác nhận `yes`.

---

# Tóm tắt nhanh

```text id="pk5ht3"
Xóa 1 resource:
Remove from code
→ terraform apply

Xóa toàn bộ:
terraform destroy

Terraform dùng:
State + Dependency Graph

Workflow:
Code Change
    ↓
Plan
    ↓
Apply/Destroy
    ↓
Update State
```
