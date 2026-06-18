# 02 — External Secrets Operator (ESO)

> **Scope:** Install, SecretStore, ExternalSecret CRD, refreshInterval, zero-restart sync

---

## 1. ESO là gì?

**External Secrets Operator** = K8s operator tự động sync secrets từ external providers (AWS Secrets Manager, HashiCorp Vault, GCP Secret Manager, Azure Key Vault) vào K8s Secrets.

```
┌─────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                     │
│                                                           │
│  ┌──────────────┐     ┌──────────────┐    ┌──────────┐  │
│  │ ExternalSecret│────►│ ESO Controller│───►│ K8s      │  │
│  │ (CRD)        │     │ (reconcile)  │    │ Secret   │  │
│  │              │     │              │    │ (synced) │  │
│  │ refreshInterval:   │              │    │          │  │
│  │   1m         │     │              │    │          │  │
│  └──────────────┘     └──────┬───────┘    └────┬─────┘  │
│                              │                  │        │
│                              │ API call         │ mount  │
│                              │                  ▼        │
│                              │           ┌──────────┐   │
│                              │           │   Pod     │   │
│  ┌──────────────┐            │           │ (auto-    │   │
│  │ SecretStore  │◄───────────┘           │  update)  │   │
│  │ (auth config)│                        └──────────┘   │
│  └──────┬───────┘                                        │
│         │                                                │
└─────────┼────────────────────────────────────────────────┘
          │ IRSA / credentials
          ▼
┌─────────────────────┐
│  AWS Secrets Manager │
│  (source of truth)   │
└─────────────────────┘
```

### Tại sao ESO thay vì mount secrets trực tiếp?

| Approach | Vấn đề |
|---|---|
| Hardcode trong manifest | ❌ Secrets trong Git |
| K8s Secret từ `kubectl create secret` | ❌ Không rotation, manual |
| Sealed Secrets | ⚠️ Encrypt at rest, nhưng không auto-sync |
| CSI Secret Store Driver | ⚠️ Mount vào pod, nhưng phức tạp |
| **ESO** | ✅ Auto-sync, auto-refresh, zero-restart |

---

## 2. Installation

```bash
# Helm install
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true \
  --set webhook.port=9443 \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="arn:aws:iam::123456789012:role/eso-secrets-reader"

# Verify
kubectl get pods -n external-secrets
# NAME                                          READY   STATUS
# external-secrets-xxx                          1/1     Running
# external-secrets-cert-controller-xxx          1/1     Running
# external-secrets-webhook-xxx                  1/1     Running

# Check CRDs
kubectl get crd | grep external-secrets
# clustersecretstores.external-secrets.io
# externalsecrets.external-secrets.io
# secretstores.external-secrets.io
```

---

## 3. SecretStore — Kết nối provider

### ClusterSecretStore (cluster-wide, recommended)

```yaml
# cluster-secret-store.yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: ap-southeast-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
```

### SecretStore (namespace-scoped)

```yaml
# secret-store.yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets
  namespace: production
spec:
  provider:
    aws:
      service: SecretsManager
      region: ap-southeast-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
```

---

## 4. ExternalSecret — Sync secrets

### Ví dụ 1: Database credentials

```yaml
# external-secret-db.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
  namespace: production
spec:
  refreshInterval: 1m            # Sync mỗi 1 phút
  
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  
  target:
    name: db-credentials          # Tên K8s Secret sẽ được tạo
    creationPolicy: Owner         # ESO owns this secret
    deletionPolicy: Retain        # Giữ secret nếu ExternalSecret bị xoá
    template:
      type: Opaque
      metadata:
        labels:
          app: myapp
          managed-by: external-secrets
  
  data:
    # Lấy từng field từ JSON secret
    - secretKey: DB_HOST          # Key trong K8s Secret
      remoteRef:
        key: production/myapp/database   # Secret name trong AWS
        property: host            # JSON field
    
    - secretKey: DB_PORT
      remoteRef:
        key: production/myapp/database
        property: port
    
    - secretKey: DB_USERNAME
      remoteRef:
        key: production/myapp/database
        property: username
    
    - secretKey: DB_PASSWORD
      remoteRef:
        key: production/myapp/database
        property: password
    
    - secretKey: DB_NAME
      remoteRef:
        key: production/myapp/database
        property: dbname
```

### Ví dụ 2: Lấy toàn bộ JSON secret

```yaml
# external-secret-full-json.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: api-keys
  namespace: production
spec:
  refreshInterval: 5m
  
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  
  target:
    name: api-keys
    creationPolicy: Owner
  
  dataFrom:
    - extract:
        key: production/myapp/api-keys
        # Mỗi JSON field trở thành 1 key trong K8s Secret
        # {"stripe_key": "sk_xxx", "sendgrid_key": "SG.xxx"}
        # → K8s Secret: stripe_key=sk_xxx, sendgrid_key=SG.xxx
```

### Ví dụ 3: Template — Format secret output

```yaml
# external-secret-template.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-connection-string
  namespace: production
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: aws-secrets-manager
    kind: ClusterSecretStore
  
  target:
    name: db-connection-string
    template:
      engineVersion: v2
      data:
        # Template tạo connection string từ individual fields
        DATABASE_URL: "postgresql://{{ .username }}:{{ .password }}@{{ .host }}:{{ .port }}/{{ .dbname }}?sslmode=require"
  
  data:
    - secretKey: username
      remoteRef:
        key: production/myapp/database
        property: username
    - secretKey: password
      remoteRef:
        key: production/myapp/database
        property: password
    - secretKey: host
      remoteRef:
        key: production/myapp/database
        property: host
    - secretKey: port
      remoteRef:
        key: production/myapp/database
        property: port
    - secretKey: dbname
      remoteRef:
        key: production/myapp/database
        property: dbname
```

---

## 5. refreshInterval — Zero-restart Secret Sync

`refreshInterval` = ESO poll AWS Secrets Manager theo interval này.

```
refreshInterval: 1m
    │
    ▼
T0:  ESO sync → K8s Secret = "password_v1"
T30: AWS rotate → Secrets Manager = "password_v2"  
T60: ESO sync → K8s Secret = "password_v2" ← Auto-updated!
    │
    ▼
Pod dùng envFrom hoặc volume mount sẽ thấy value mới
```

### Volume mount vs envFrom

| Mount type | Auto-update | Cần restart pod? |
|---|---|---|
| Volume mount (`volumeMounts`) | ✅ kubelet sync (~1 min) | ❌ Không cần |
| Environment variable (`envFrom`) | ❌ Env cố định khi pod start | ✅ Cần restart |

```yaml
# RECOMMENDED: Volume mount cho zero-restart
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    spec:
      containers:
        - name: app
          image: myapp:v1
          volumeMounts:
            - name: db-creds
              mountPath: /etc/secrets/db
              readOnly: true
          # App đọc file: /etc/secrets/db/DB_PASSWORD
          # File tự update khi secret thay đổi
      volumes:
        - name: db-creds
          secret:
            secretName: db-credentials

# ALTERNATIVE: envFrom (cần Reloader để auto-restart)
# Xem Stakater Reloader: https://github.com/stakater/Reloader
```

### Stakater Reloader — Auto-restart khi secret thay đổi

```yaml
# Nếu app PHẢI dùng env var (không đọc file):
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  annotations:
    # Reloader watch secret này, restart pod khi thay đổi
    secret.reloader.stakater.com/reload: "db-credentials"
spec:
  template:
    spec:
      containers:
        - name: app
          envFrom:
            - secretRef:
                name: db-credentials
```

---

## 6. Verify Setup

```bash
# Check ExternalSecret status
kubectl get externalsecret -n production
# NAME              STORE                  REFRESH INTERVAL   STATUS
# db-credentials    aws-secrets-manager    1m                 SecretSynced

# Check synced K8s secret
kubectl get secret db-credentials -n production -o yaml

# Check last sync time
kubectl get externalsecret db-credentials -n production -o jsonpath='{.status.conditions}'

# Check SecretStore connectivity
kubectl get secretstore -n production
kubectl get clustersecretstore

# Debug: xem ESO logs
kubectl logs -n external-secrets deployment/external-secrets -f
```

---

## 7. Troubleshooting

| Issue | Check |
|---|---|
| `SecretSyncedError` | IRSA role đúng chưa? IAM policy có `GetSecretValue`? |
| `ProviderError` | Secret name đúng không? Region đúng? |
| Secret không update | `refreshInterval` quá lớn? ESO pod running? |
| Permission denied | ServiceAccount có annotation IRSA? Trust policy đúng? |

```bash
# Quick debug
kubectl describe externalsecret db-credentials -n production
# Xem Events section → error message chi tiết

# Check IAM
aws sts get-caller-identity  # Verify role
aws secretsmanager get-secret-value --secret-id production/myapp/database  # Test access
```
