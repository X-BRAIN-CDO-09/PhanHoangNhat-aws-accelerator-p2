# 03 — Chaos Testing

> **Scope:** Chaos engineering principles, Litmus/Chaos Mesh, pod kill, network chaos, steady-state verification

---

## 1. Chaos Engineering là gì?

**Chaos Engineering** = "Cố tình gây lỗi trong controlled environment để phát hiện weakness TRƯỚC KHI production gặp lỗi thật."

```
Chaos Engineering Cycle:
1. Define steady state  → "App trả response < 200ms, 99.9% success rate"
2. Hypothesize          → "Nếu kill 1 pod, HPA tạo pod mới < 30s, users không thấy error"
3. Inject chaos         → Kill pod
4. Observe              → HPA có tạo pod mới không? Latency có spike?
5. Analyze              → Kết quả khớp hypothesis? Nếu không → fix!
6. Improve              → Fix weakness, lặp lại test
```

### Tại sao cần cho platform team?

```
Scenario: Production 3 AM
├── Node bị drain (spot instance reclaim)
├── Pod bị kill (OOMKill)
├── Network partition giữa services
├── Secret rotation → app crash
├── Database failover
└── DNS propagation delay

Không chaos test → "Hy vọng nó sẽ tự heal" 🙏
Có chaos test → "Đã test, biết chắc hệ thống recover trong 30s" ✅
```

---

## 2. Litmus Chaos

**LitmusChaos** (by Harness) = CNCF project cho Kubernetes chaos engineering.

### Install

```bash
# Helm install
helm repo add litmuschaos https://litmuschaos.github.io/litmus-helm
helm repo update

helm install litmus litmuschaos/litmus \
  --namespace litmus \
  --create-namespace \
  --set portal.frontend.service.type=ClusterIP

# Install chaos experiments
kubectl apply -f https://hub.litmuschaos.io/api/chaos/3.0.0?file=charts/generic/experiments.yaml \
  -n litmus
```

### Experiment: Pod Delete

```yaml
# chaos-pod-delete.yaml
apiVersion: litmuschaos.io/v1alpha1
kind: ChaosEngine
metadata:
  name: pod-delete-test
  namespace: staging
spec:
  engineState: active
  appinfo:
    appns: staging
    applabel: app=myapp
    appkind: deployment
  chaosServiceAccount: litmus-admin
  experiments:
    - name: pod-delete
      spec:
        components:
          env:
            - name: TOTAL_CHAOS_DURATION
              value: "30"            # 30 giây chaos
            - name: CHAOS_INTERVAL
              value: "10"            # Kill pod mỗi 10 giây
            - name: FORCE
              value: "true"          # Force delete (no grace period)
            - name: PODS_AFFECTED_PERC
              value: "50"            # Kill 50% pods
        probe:
          - name: check-app-health
            type: httpProbe
            httpProbe/inputs:
              url: "http://myapp.staging.svc:8080/health"
              method:
                get:
                  criteria: ==
                  responseCode: "200"
            mode: Continuous
            runProperties:
              probeTimeout: 5
              retry: 3
              interval: 5
```

### Experiment: Network Chaos (Latency)

```yaml
# chaos-network-latency.yaml
apiVersion: litmuschaos.io/v1alpha1
kind: ChaosEngine
metadata:
  name: network-latency-test
  namespace: staging
spec:
  engineState: active
  appinfo:
    appns: staging
    applabel: app=myapp
    appkind: deployment
  chaosServiceAccount: litmus-admin
  experiments:
    - name: pod-network-latency
      spec:
        components:
          env:
            - name: TOTAL_CHAOS_DURATION
              value: "60"
            - name: NETWORK_LATENCY
              value: "300"           # 300ms latency
            - name: NETWORK_INTERFACE
              value: "eth0"
            - name: DESTINATION_IPS
              value: ""              # All traffic
```

---

## 3. Chaos Mesh (Alternative)

**Chaos Mesh** (by PingCAP / CNCF) = another popular chaos engineering platform.

### Install

```bash
helm repo add chaos-mesh https://charts.chaos-mesh.org
helm repo update

helm install chaos-mesh chaos-mesh/chaos-mesh \
  --namespace chaos-mesh \
  --create-namespace \
  --set chaosDaemon.runtime=containerd \
  --set chaosDaemon.socketPath=/run/containerd/containerd.sock
```

### Pod Kill

```yaml
# chaos-mesh-pod-kill.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: PodChaos
metadata:
  name: pod-kill-test
  namespace: staging
spec:
  action: pod-kill
  mode: one                          # Kill 1 pod tại 1 thời điểm
  selector:
    namespaces:
      - staging
    labelSelectors:
      app: myapp
  duration: "30s"
  scheduler:
    cron: "@every 2m"                # Lặp lại mỗi 2 phút (optional)
```

### Network Partition

```yaml
# chaos-mesh-network-partition.yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: NetworkChaos
metadata:
  name: network-partition-test
  namespace: staging
spec:
  action: partition
  mode: all
  selector:
    namespaces:
      - staging
    labelSelectors:
      app: myapp
  direction: both                    # Cả inbound + outbound
  target:
    selector:
      namespaces:
        - staging
      labelSelectors:
        app: database               # Partition myapp ↔ database
    mode: all
  duration: "30s"
```

### CPU Stress

```yaml
apiVersion: chaos-mesh.org/v1alpha1
kind: StressChaos
metadata:
  name: cpu-stress-test
  namespace: staging
spec:
  mode: one
  selector:
    namespaces:
      - staging
    labelSelectors:
      app: myapp
  stressors:
    cpu:
      workers: 2                     # 2 CPU stress workers
      load: 80                       # 80% CPU usage
  duration: "60s"
```

---

## 4. Chaos Test Scenarios cho W10 Platform

| # | Test | Hypothesis | Verify |
|---|---|---|---|
| 1 | Kill 1/3 app pods | HPA tạo pod mới < 30s, no user error | `kubectl get pods --watch`, latency dashboard |
| 2 | Kill Gatekeeper pod | Webhook unavailable → failOpen, no block | `kubectl apply` resource during chaos |
| 3 | Network partition app ↔ DB | Circuit breaker trigger, graceful degradation | Error rate dashboard, fallback response |
| 4 | Rotate secret (ESO) | App tự reload secret < 60s, no restart | ESO status, app logs |
| 5 | Node drain | Pods reschedule to other nodes < 2min | `kubectl get pods -o wide` |
| 6 | DNS failure | App retry + cache, recover khi DNS lên | Request success rate |

### Test Script

```bash
#!/bin/bash
# chaos-test.sh — Run basic chaos tests

echo "=== Chaos Test Suite ==="
echo ""

# Test 1: Pod Delete
echo "🔥 Test 1: Kill 1 pod"
POD=$(kubectl get pod -n staging -l app=myapp -o jsonpath='{.items[0].metadata.name}')
echo "  Killing pod: $POD"

# Record start time
START=$(date +%s)

# Delete pod
kubectl delete pod $POD -n staging --grace-period=0 --force

# Wait for replacement
echo "  Waiting for replacement pod..."
kubectl wait --for=condition=ready pod -l app=myapp -n staging --timeout=60s

END=$(date +%s)
RECOVERY=$((END - START))
echo "  ✅ Recovery time: ${RECOVERY}s"

if [ $RECOVERY -le 30 ]; then
  echo "  ✅ PASS: Recovery < 30s"
else
  echo "  ❌ FAIL: Recovery > 30s"
fi

echo ""

# Test 2: Check Gatekeeper resilience
echo "🔥 Test 2: Gatekeeper webhook availability"
kubectl get validatingwebhookconfigurations gatekeeper-validating-webhook-configuration &>/dev/null
if [ $? -eq 0 ]; then
  echo "  ✅ Gatekeeper webhook active"
else
  echo "  ⚠️ Gatekeeper webhook not found"
fi

echo ""
echo "=== Tests Complete ==="
```

---

## 5. Steady-State Metrics

Trước khi chạy chaos, define steady state:

```yaml
# steady-state.yaml (documentation)
steadyState:
  metrics:
    - name: request_success_rate
      query: "rate(http_requests_total{status=~'2..'}[5m]) / rate(http_requests_total[5m]) * 100"
      threshold: ">= 99.9"
    
    - name: p99_latency
      query: "histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))"
      threshold: "<= 0.5"          # 500ms
    
    - name: pod_count
      query: "count(kube_pod_info{namespace='production', pod=~'myapp-.*'})"
      threshold: ">= 3"           # Minimum 3 replicas
    
    - name: error_rate
      query: "rate(http_requests_total{status=~'5..'}[5m])"
      threshold: "<= 0.001"       # < 0.1%
```

---

## 6. Best Practices

| Practice | Giải thích |
|---|---|
| **Start small** | Pod kill trước, network chaos sau |
| **Staging first** | KHÔNG chạy chaos trực tiếp trên production |
| **Define hypothesis** | Biết expected outcome trước khi test |
| **Monitor during chaos** | Dashboard Grafana mở sẵn |
| **Blast radius** | Giới hạn scope (1 pod, 1 namespace) |
| **Kill switch** | Luôn có cách stop chaos ngay lập tức |
| **Document results** | Mỗi test có report |
| **Gameday** | Schedule chaos test có kế hoạch |
