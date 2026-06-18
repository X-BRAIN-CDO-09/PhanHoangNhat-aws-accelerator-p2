# Secret Rotation Runbook

## Tổng quan

External Secrets Operator (ESO) tự động sync secret từ AWS Secrets Manager vào Kubernetes mà **không cần restart pod**.

---

## ESO Flow

```
AWS Secrets Manager
    (demo/db/password)
         │
         │ poll mỗi 1 phút
         ▼
  ESO Controller
  (external-secrets namespace)
         │
         │ reconcile
         ▼
  K8s Secret: db-secret
  (namespace: demo)
         │
         │ kubelet volume sync (~1 phút)
         ▼
  Pod filesystem: /etc/secrets/password
  (AGE của pod KHÔNG đổi ✅)
```

---

## Cách thay đổi password ở AWS

### 1. Update secret trong AWS Console

```bash
# Hoặc dùng AWS CLI:
aws secretsmanager put-secret-value \
  --secret-id demo/db/password \
  --secret-string '{"password":"new-super-secret-password-2024"}' \
  --region ap-southeast-1
```

### 2. ESO tự động phát hiện thay đổi

ESO poll mỗi `refreshInterval: 1m` (cấu hình trong `eso/external-secret.yaml`).

### 3. K8s Secret tự update

```bash
# Verify K8s secret đã được update (chờ tối đa 60 giây):
kubectl get secret db-secret -n demo \
  -o jsonpath='{.data.password}' | base64 -d && echo

# Xem thời gian update:
kubectl get secret db-secret -n demo \
  -o jsonpath='{.metadata.annotations.reconcile\.external-secrets\.io/last-reconcile-time}'
```

### 4. Verify pod KHÔNG restart

```bash
# AGE của pod phải KHÔNG đổi sau khi secret được update
kubectl get pod -n demo -l app=api

# Output mong đợi: AGE giữ nguyên ✅
# NAME        READY   STATUS    RESTARTS   AGE
# api-xxxx    1/1     Running   0          2h  ← AGE không thay đổi
```

### 5. Verify file trong pod đã được update

```bash
# Đọc file secret trong pod (kubelet tự sync volume sau ~1 phút):
kubectl exec -n demo \
  $(kubectl get pod -n demo -l app=api -o name | head -1) \
  -- cat /etc/secrets/password
```

---

## Tại sao pod không restart?

- Secret được mount qua **volumeMount** (không phải env var)
- Khi K8s Secret được update, **kubelet tự động sync** nội dung file trong volume
- **env var** sẽ KHÔNG thay đổi nếu không restart pod
- **volumeMount file** được sync mà không cần restart → AGE giữ nguyên

---

## Verify ExternalSecret status

```bash
# Kiểm tra ESO sync thành công:
kubectl get externalsecret db-secret -n demo

# Output mong đợi:
# NAME        STORE                 REFRESH INTERVAL   STATUS         READY
# db-secret   aws-secrets-manager   1m                 SecretSynced   True

# Xem chi tiết:
kubectl describe externalsecret db-secret -n demo
```

---

## Troubleshoot

```bash
# ESO controller logs:
kubectl logs -n external-secrets \
  -l app.kubernetes.io/name=external-secrets \
  --tail=50

# SecretStore status:
kubectl get secretstore aws-secrets-manager -n demo -o yaml

# Xác nhận aws-creds secret tồn tại:
kubectl get secret aws-creds -n demo
```

---

## Tạo aws-creds (chỉ làm 1 lần, KHÔNG commit lên git)

```bash
kubectl create secret generic aws-creds \
  --from-literal=access-key=YOUR_AWS_ACCESS_KEY_ID \
  --from-literal=secret-access-key=YOUR_AWS_SECRET_ACCESS_KEY \
  -n demo
```

> ⚠️ **KHÔNG commit credential vào git.** File `aws-creds` được thêm vào `.gitignore`.
