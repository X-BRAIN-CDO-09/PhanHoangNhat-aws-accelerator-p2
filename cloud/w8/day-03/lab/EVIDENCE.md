# 📸 Evidence — Final Project: Deploy a Web App on AWS

> **Week 8 · Day 3 Lab** | Họ tên: Phan Hoàng Nhật  
> **Ngày thực hiện**: 2026-06-08 | **Region**: ap-southeast-1 | **Account**: 312513453992

---

## Evidence 1 — Terraform Apply thành công

> Chụp terminal sau lệnh `terraform apply` — thấy số resources đã tạo và danh sách outputs (EC2 IP, RDS endpoint, S3 bucket)

<!-- BỎ SCREENSHOT VÀO ĐÂY -->
![Terraform Apply Complete](./Screen_evidence/01_terraform_apply_complete.png)

---

## Evidence 2 — EC2 (Public) + RDS (Private) đã tạo trên AWS

> **EC2**: Console → EC2 Instances → `webapp-web-server` đang **Running**, Subnet = public  
> **RDS**: Console → RDS Databases → `webapp-mysql` **Available**, **Publicly accessible: No**

<!-- BỎ SCREENSHOT EC2 VÀO ĐÂY -->
![EC2 Running in Public Subnet](./Screen_evidence/02_ec2_running.png)

<!-- BỎ SCREENSHOT RDS VÀO ĐÂY -->
![RDS MySQL in Private Subnet - Not Public](./Screen_evidence/02_rds_private.png)

---

## Evidence 3 — Web App chạy được trên browser

> Mở browser → `http://<EC2_PUBLIC_IP>` — thấy trang web hiển thị thông tin EC2, RDS status, S3 bucket

<!-- BỎ SCREENSHOT VÀO ĐÂY -->
![Web App Accessible via HTTP](./Screen_evidence/03_web_app_browser.png)

---

## Evidence 4 — S3 Backend State + RDS Security Group

> **S3 Backend**: S3 → `s3-terraform-remote-lab` → `w8/day-03/lab/terraform.tfstate` tồn tại  
> **Security Group**: RDS SG → Inbound rules → port 3306 chỉ từ EC2 Security Group (không phải 0.0.0.0/0)

<!-- BỎ SCREENSHOT S3 STATE VÀO ĐÂY -->
![S3 Backend - terraform.tfstate](./Screen_evidence/04_s3_state_file.png)

<!-- BỎ SCREENSHOT RDS SG VÀO ĐÂY -->
![RDS SG - MySQL only from EC2 SG](./Screen_evidence/04_rds_sg_ec2_only.png)

---

*W8 Day 3 Lab · PhanHoangNhat AWS Accelerator P2*
