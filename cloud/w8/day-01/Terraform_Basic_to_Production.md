# Infrastructure as Code, What Terraform Is, and Getting to Know the CLI

## Vấn đề

- Không tái lập được
- **Trôi dạt cấu hình** (drift). Ví dụ có sự cố bất chợt, và đã sử lí nhưng quên ghi chép lại. Rồi vài tuần sau sẽ không biết hệ thông thực tế khác gì ý định ban đầu vì thay đổi không được ghi chép lại
- Không thể kiểm tra được. Khi thay đổi bằng giao diện người dùng thì chỉ có click không có dấu vết ai đó duyệt trước khi thay đổi

> **IaC giải quyết các vấn đề đó**

## Vòng đời

**HashiCorp** gói quy trình Terraform thành ba bước:

1. **Write** — bạn định nghĩa resource trong file `.tf`, có thể trải trên nhiều provider
2. **Plan** — Terraform tạo một execution plan, mô tả nó sẽ tạo, sửa hay xóa cái gì, dựa trên hiện trạng và cấu hình của bạn
3. **Apply** — sau khi bạn duyệt, Terraform thực hiện các thao tác đó _"theo đúng thứ tự, tôn trọng mọi quan hệ phụ thuộc giữa resource"_

Cộng thêm **`destroy`** để dỡ bỏ những gì đã tạo, đó là **vòng đời cơ bản**.

## Core nói chuyện với Provider ra sao

**Terraform** dựng hai khối riêng biệt:

- **Terraform Core** — Binary cài đặt. Cho đọc file `.tf`, dựng đồ thị các resource và quan hệ giữa chúng, đối chiếu state. Core không chứa thông tin về AWS

- **Provider** — Binary riêng, tải lúc `terraform init` và nằm trong thư mục `.terraform`. Khai báo schema của resource và gọi API thật. Khi core tạo resource thì gửi yêu cầu qua **gRPC** trên localhost (Cơ chế go-plugin của HashiCorp) và gửi cho provider AWS

- **State File** — Core ghi id thật cùng toàn bộ thuộc tính vào `terraform.tfstate`

> **Tách core ra khỏi provider là lí do công cụ quản lí các nền tảng cùng lúc trong cùng lần apply**

## Giấy phép

- Từ phiên bản **1.6** (tháng 8/2023), Terraform chuyển giấy phép **MPL 2.0** sang **Business Source License 1.1 (BUSL)**
- Việc chuyển này chỉ hạn chế duy nhất Terraform làm sản phẩm cạnh tranh thương mại với HashiCorp
- **OpenTofu** ra đời vì lí do này, là bản fork giữ giấy phép mã nguồn mở

> **Người dùng cá nhân và công ty dùng Terraform vẫn dùng miễn phí**

## Cài đặt

- **Phiên bản quan trọng** hơn bạn nghĩ: nhiều tính năng ta sẽ dùng (`state lock` bằng `use_lockfile`, `ephemeral resources`, các block `import`/`moved`/`removed`) chỉ có ở những bản gần đây
- Mỗi bài sẽ ghi rõ tính năng nào cần bản nào

## Một vòng các lệnh CLI

### Nhóm lệnh cơ bản

```bash
$ terraform -help
Usage: terraform [global options] <subcommand> [args]
...
Main commands:
  init          Chuẩn bị thư mục làm việc
  validate      Kiểm tra cú pháp cấu hình đạt yêu cầu
  plan          Xem trước thay đổi
  apply         Tạo hoặc nâng cấp cấu hình
  destroy       Hủy các cấu hình
```

### Nhóm lệnh ít gặp nhưng cần khi đi sâu

```bash
All other commands:
  console       Thử nghiệm các biểu thức Terraform tại dấu nhắc lệnh tương tác
  fmt           Định dạng lại các tệp cấu hình theo chuẩn Terraform
  graph         Tạo đồ thị Graphviz mô tả các bước hoặc phụ thuộc
  import        Liên kết hạ tầng đã tồn tại với một resource
  output        Hiển thị các output values từ module gốc
  providers     Hiển thị các provider mà cấu hình yêu cầu
  show          Hiển thị state hiện tại hoặc một plan đã lưu
  state         Thực hiện các thao tác quản lý state nâng cao
  test          Thực hiện các thao tác quản lý state nâng cao
  ...
```

### Mẹo nhỏ: Autocomplete

Bật autocomplete cho shell, gõ `terraform` rồi **Tab** sẽ gợi ý lệnh:

```bash
terraform -install-autocomplete
```

> Lệnh này thêm cấu hình vào `~/.bashrc` hoặc `~/.zshrc`; mở shell mới để nó có hiệu lực.
