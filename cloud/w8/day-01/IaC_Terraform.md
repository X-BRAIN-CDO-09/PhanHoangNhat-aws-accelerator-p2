# Infrastructure as Code (IaC)

**Infrastructure as Code (IaC)** tools cho phép quản lí hạ tầng với tệp cấu hình thay vì thông qua giao diện người dùng. IaC cho phép xây dựng, thay đổi và quản lí hạ tầng một cách an toàn, thống nhất và lặp lại bằng cách định nghĩa các nguồn tài nguyên để mà làm các phiên bản, tái sử dụng và chia sẻ.

## Terraform là gì?

**Terraform** là **HashiCorp's IaC tool**. Terraform cho phép định nghĩa các tài nguyên và hạ tầng để con người có thể đọc được, khai báo các tệp cấu hình và quản lý vòng đời hạ tầng.

### Lợi ích của Terraform

- Terraform có thể quản lí hạ tầng trên nhiều nền tảng Cloud
- Ngôn ngữ cấu hình phù hợp cho người đọc giúp viết code hạ tầng nhanh chóng
- **Terraform state** cho phép theo dõi các tài nguyên thay đổi thông qua việc triển khai
- Các tệp cấu hình với hệ thống quản lí phiên bản cho phép cộng tác an toàn

## Quản lí bất cứ hạ tầng nào

**Terraform providers** là các plugin cho phép tương tác với các nền tảng cloud và các dịch vụ khác thông qua APIs. **HashiCorp** và cộng đồng Terraform có hơn **1.000 providers** để quản lí tài nguyên. Có thể tìm kiếm providers thông qua **Terraform Registry**

## Chuẩn hóa quy trình triển khai

**Providers** định nghĩa từng đơn vị của hạ tầng. Chúng ta có thể kết hợp các tài nguyên từ các providers thành các **Terraform modules** có thể tái sử dụng, và quản lí chúng với ngôn ngữ và quy trình thống nhất

Ngôn ngữ cấu hình **Terraform** là **declarative (Khai báo)**. Nghĩa là chỉ cần miêu tả trạng thái thay vì viết từng bước thực hiện.

### Quy trình triển khai với Terraform

- **Scope** — Xác định hạ tầng của dự án
- **Author** — Viết cấu hình cho hạ tầng
- **Initialize** — Tải các plugins Terraform cần thiết để quản lí hạ tầng
- **Plan** — Xem trước các thay đổi Terraform sẽ thực hiện để phù hợp với cấu hình
- **Apply** — Thực hiện các thay đổi đã lên kế hoạch

## Theo dõi hạ tầng

- Terraform giữ việc theo dõi hạ tầng trong **state file**, nó là nguồn tham chiếu chính xác cho môi trường của bạn

## Cộng tác

- **Terraform** cho phép cộng tác trên hạ tầng với các trạng thái bên ngoài (**Remote state backend**). Khi sử dụng **HCP Terraform** (miễn phí tới 5 người dùng), bảo mật chia sẻ state với đồng đội, cung cấp môi trường ổn định để Terraform chạy, và ngăn chặn tranh chấp khi nhiều người chỉnh sửa cấu hình cùng lúc
- Kết nối **HCP Terraform** tới **VCS (Version Control System)** cho phép tự động đề xuất thay đổi khi commit cấu hình. Cho phép quản lí thay đổi hạ tầng thông qua version control
