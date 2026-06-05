#!/bin/bash
# =============================================================================
# user_data.sh.tpl — Bootstrap script for EC2 Ubuntu
# Runs as root via cloud-init on first boot.
#
# Terraform templatefile() variables:
#   ${node_port}    — Kubernetes NodePort (e.g., 30080)
#   ${cluster_name} — kind cluster name (e.g., demo-cluster)
#
# Bash variables are escaped with $${...} so Terraform does NOT interpolate them.
# =============================================================================

set -euo pipefail
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "=== [1/5] System update + base tools ==="
apt-get update -y
apt-get install -y ca-certificates curl socat conntrack

echo "=== [2/5] Install Docker via official convenience script ==="
# Uses Docker's get.docker.com — handles GPG key and apt repo automatically.
# No manual docker.list setup needed.
curl -fsSL https://get.docker.com | sh
usermod -aG docker ubuntu
systemctl enable docker
systemctl start docker
docker --version

echo "=== [3/5] Install kubectl ==="
KUBECTL_VERSION="v1.29.0"
curl -fsSL "https://dl.k8s.io/release/$${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
  -o /usr/local/bin/kubectl
chmod +x /usr/local/bin/kubectl
kubectl version --client

echo "=== [4/5] Install kind ==="
KIND_VERSION="v0.23.0"
curl -fsSL "https://kind.sigs.k8s.io/dl/$${KIND_VERSION}/kind-linux-amd64" \
  -o /usr/local/bin/kind
chmod +x /usr/local/bin/kind
kind version

echo "=== [5/5] Create kind cluster ==="
cat > /tmp/kind-config.yaml <<'KINDEOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: ${node_port}
        hostPort: ${node_port}
        protocol: TCP
KINDEOF

kind create cluster --name ${cluster_name} --config /tmp/kind-config.yaml --wait 5m

mkdir -p /home/ubuntu/.kube
kind get kubeconfig --name ${cluster_name} > /home/ubuntu/.kube/config
chown -R ubuntu:ubuntu /home/ubuntu/.kube
kind get kubeconfig --name ${cluster_name} > /var/tmp/kubeconfig
chmod 644 /var/tmp/kubeconfig

kubectl get nodes

echo "=== Bootstrap complete! ==="
