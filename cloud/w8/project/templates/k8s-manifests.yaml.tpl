---
# =============================================================================
# k8s-manifests.yaml.tpl — Kubernetes manifests
#
# IMPORTANT: image: demo-app:latest with imagePullPolicy: Never
# The image is built on EC2 and loaded into kind via:
#   docker build -t demo-app:latest ./app-build
#   kind load docker-image demo-app:latest --name <cluster>
# =============================================================================

# ── Namespace ─────────────────────────────────────────────────────────────────
apiVersion: v1
kind: Namespace
metadata:
  name: demo
  labels:
    project: ${project_name}

---
# ── Deployment ────────────────────────────────────────────────────────────────
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-app
  namespace: demo
  labels:
    app: demo-app
    project: ${project_name}
spec:
  replicas: 2
  selector:
    matchLabels:
      app: demo-app
  template:
    metadata:
      labels:
        app: demo-app
        project: ${project_name}
    spec:
      containers:
        - name: app
          image: demo-app:latest
          # Never pull from registry — image is loaded locally into kind
          imagePullPolicy: Never
          ports:
            - containerPort: 80
              name: http
          resources:
            requests:
              cpu: "50m"
              memory: "64Mi"
            limits:
              cpu: "200m"
              memory: "128Mi"
          readinessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 3
            periodSeconds: 5
            failureThreshold: 3
          livenessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 10
            periodSeconds: 15
            failureThreshold: 3

---
# ── Service (NodePort) ────────────────────────────────────────────────────────
apiVersion: v1
kind: Service
metadata:
  name: demo-app-svc
  namespace: demo
  labels:
    app: demo-app
    project: ${project_name}
spec:
  type: NodePort
  selector:
    app: demo-app
  ports:
    - name: http
      protocol: TCP
      port: 80
      targetPort: 80
      nodePort: ${node_port}
