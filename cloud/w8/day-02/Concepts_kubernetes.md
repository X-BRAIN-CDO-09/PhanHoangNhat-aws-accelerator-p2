## 1. Tổng quan (Overview)

### Khái niệm

- Kubernetes (K8s) là nền tảng **điều phối container**: triển khai, cập nhật, mở rộng, tự phục hồi ứng dụng.
- Bạn mô tả **desired state** (trạng thái mong muốn) bằng YAML/manifest; các controller sẽ liên tục **reconcile** để khớp trạng thái thực tế.

### Điểm cần nhớ

- **Declarative** (khai báo) là cách làm chuẩn: `kubectl apply -f ...`.
- **Self-healing**: Pod chết → tạo lại; node lỗi → dời workload.
- **Rollout/Rollback**: cập nhật theo từng bước, có thể quay lại phiên bản trước.

### Lệnh nhanh

```bash
kubectl get nodes
kubectl get ns
kubectl get all -n <namespace>
kubectl describe <kind> <name> -n <namespace>
```

## 2. Kiến trúc cụm (Cluster Architecture)

### Control Plane

- `kube-apiserver`: cổng API; mọi thao tác đều thông qua API Server.
- `etcd`: DB key-value lưu trạng thái cluster (source of truth).
- `kube-scheduler`: chọn node phù hợp để chạy Pod.
- `kube-controller-manager`: chạy các controller để duy trì desired state.

### Worker Node

- `kubelet`: agent trên node, nhận PodSpec và đảm bảo container chạy đúng.
- `kube-proxy`: tạo luật mạng để Service hoạt động.
- Container runtime: `containerd`, `CRI-O`… (theo CRI).

### Lưu ý vận hành

- Backup/restore `etcd` là cực kỳ quan trọng với cluster tự quản.
- Kiểm soát quyền truy cập vào API Server (authn/authz) để bảo vệ cluster.

## 3. Container (Bộ chứa)

### Khái niệm

- **Image**: gói ứng dụng + dependencies (được push lên registry).
- **Container**: instance chạy từ image.
- **Registry**: Docker Hub, ECR, GCR…

### Điểm cần nhớ

- Container chia sẻ kernel → nhẹ hơn VM.
- **Tag** có thể thay đổi; **digest** (sha256) cố định nội dung image.
- Best practices:
  - image nhỏ, multi-stage build
  - log ra stdout/stderr
  - tránh chạy root nếu không cần

## 4. Workloads (Khối lượng công việc)

### Pod

- Pod là đơn vị triển khai nhỏ nhất.
- Nhiều container trong cùng Pod chia sẻ network/volume.
- Pod là ephemeral: có thể bị tạo lại và đổi IP.

### Controllers phổ biến

- `Deployment`: stateless, rolling update/rollback.
- `StatefulSet`: stateful, identity ổn định, thường gắn PVC riêng.
- `DaemonSet`: 1 Pod trên mỗi node.
- `Job`/`CronJob`: chạy 1 lần / theo lịch.

### Probes & tài nguyên

- `readinessProbe`: sẵn sàng nhận traffic.
- `livenessProbe`: treo → restart.
- `requests/limits`: ảnh hưởng scheduling và QoS.

### Ví dụ Deployment tối giản

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
        - name: web
          image: nginx:1.27
          ports:
            - containerPort: 80
```

## 5. Dịch vụ, Cân bằng tải và Mạng (Services, Load Balancing, and Networking)

### Nền tảng mạng

- Mỗi Pod có IP riêng; Pod-to-Pod giao tiếp trực tiếp (thường nhờ CNI).
- DNS nội bộ cho Service/Pod trong cluster.

### Service

- Cung cấp endpoint ổn định (virtual IP/DNS) để truy cập nhóm Pod.
- Các loại:
  - `ClusterIP`: nội bộ.
  - `NodePort`: mở cổng trên node.
  - `LoadBalancer`: tạo LB từ cloud provider.

### Ingress

- Định tuyến HTTP/HTTPS theo host/path vào Service.
- Cần Ingress Controller (Nginx, ALB…).

### Lệnh nhanh

```bash
kubectl get svc -A
kubectl get ingress -A
kubectl get endpointslices -n <namespace>
```

## 6. Lưu trữ (Storage)

### Khái niệm

- Ephemeral volume: mất theo vòng đời Pod.
- Persistent storage: tồn tại độc lập với Pod (PV/PVC).

### PV/PVC/StorageClass

- PV: tài nguyên lưu trữ.
- PVC: yêu cầu lưu trữ của workload.
- StorageClass: mô tả loại/kiểu cấp phát (dynamic provisioning).

### Ví dụ PVC

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
```

## 7. Cấu hình (Configuration)

### ConfigMap

- Lưu cấu hình không nhạy cảm (key/value hoặc file).
- Inject vào Pod qua env hoặc mount file.

### Secret

- Lưu dữ liệu nhạy cảm (password, token, cert).
- Lưu ý: base64 trong YAML không đồng nghĩa mã hóa mạnh; cần giới hạn RBAC và (nếu có) encryption at rest.

### Ví dụ dùng Secret làm env

```yaml
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: db-secret
        key: password
```

## 8. Bảo mật (Security)

### Authn/Authz/Admission

- Authentication: xác minh danh tính.
- Authorization: RBAC quyết định quyền.
- Admission: policy kiểm tra/biến đổi request trước khi lưu vào etcd.

### RBAC căn bản

- `Role`/`RoleBinding` (scope namespace)
- `ClusterRole`/`ClusterRoleBinding` (scope toàn cluster)

### Pod security

- `securityContext` (runAsNonRoot, readOnlyRootFilesystem, capabilities…)
- Pod Security Admission (Baseline/Restricted) tùy cấu hình cluster.

## 9. Chính sách (Policies)

### Quota & giới hạn

- `ResourceQuota`: giới hạn tổng tài nguyên trong namespace.
- `LimitRange`: đặt default/min/max cho container.

### NetworkPolicy

- Kiểm soát traffic ingress/egress giữa Pod/namespace.
- Yêu cầu CNI hỗ trợ.

### PDB (thường dùng trong vận hành)

- `PodDisruptionBudget`: giới hạn số Pod có thể bị gián đoạn khi drain/upgrade.

## 10. Lập lịch, Xử lý trước và Thu hồi (Scheduling, Preemption and Eviction)

### Scheduling

- `nodeSelector`: ràng buộc đơn giản.
- `nodeAffinity`: ràng buộc/ưu tiên nâng cao.
- `podAffinity`/`podAntiAffinity`: chạy gần/xa Pod khác.
- `taints`/`tolerations`: node “từ chối” Pod trừ khi Pod chịu được (tolerate).

### Preemption & Eviction

- Preemption: Pod ưu tiên cao có thể đẩy Pod ưu tiên thấp ra khỏi node.
- Eviction: node thiếu tài nguyên → kubelet evict Pod; QoS ảnh hưởng thứ tự bị evict.

## 11. Quản trị cụm (Cluster Administration)

### Công việc thường gặp

- Quản lý context/credential: `kubectl config get-contexts`.
- Bảo trì node: cordon/drain.
- Nâng cấp cluster/addon một cách có kiểm soát.
- Giám sát: events, logs, metrics.

### Lệnh nhanh

```bash
kubectl get events -A --sort-by=.lastTimestamp
kubectl cordon <node>
kubectl drain <node> --ignore-daemonsets
```

## 12. Windows trong Kubernetes

### Khái niệm

- Cluster có thể có worker node Windows (mixed OS).
- Pod Windows chỉ chạy trên Windows node.

### Điểm cần nhớ

- Một số tính năng/tuỳ chọn Linux không áp dụng tương tự trên Windows.
- Cần ràng buộc scheduling theo OS.

Ví dụ:

```yaml
nodeSelector:
  kubernetes.io/os: windows
```

## 13. Mở rộng Kubernetes (Extending Kubernetes)

### CRD

- CRD cho phép tạo loại resource mới trong Kubernetes API để mô hình hóa domain riêng.

### Operator/Controller

- Controller theo dõi resource và reconcile desired state.
- Operator đóng gói “kiến thức vận hành” ứng dụng (install/upgrade/backup/scale).

### Các cách mở rộng thường gặp

- Admission Webhook (validate/mutate).
- API Aggregation (gắn thêm API server phụ).
