# =============================================================================
# kubernetes.tf — Kubernetes resources (reference / documentation)
#
# WHY THIS FILE EXISTS AS REFERENCE:
#   The Kubernetes Terraform provider needs direct TCP access to the API server.
#   The kind cluster's API server runs on 127.0.0.1 inside the EC2 instance
#   and is NOT exposed publicly. Terraform running on your local machine
#   cannot reach it without an SSH tunnel.
#
# ACTUAL DEPLOYMENT:
#   All K8s resources are deployed via null_resource.deploy_k8s in bootstrap.tf
#   using remote-exec (kubectl apply inside EC2). This is the reliable fallback.
#
# SSH TUNNEL OPTION (advanced):
#   If you want to use the Kubernetes provider natively, set up an SSH tunnel:
#     ssh -N -L 6443:localhost:6443 -i <key.pem> ubuntu@<EC2_IP>
#   Then update generated/kubeconfig server URL to https://127.0.0.1:6443
#   and uncomment the resources below.
#
# For now, this file documents the intended K8s resource structure.
# =============================================================================

# ─────────────────────────────────────────────────────────────────────────────
# REFERENCE ONLY — These resources are NOT applied by terraform apply.
# They are deployed via null_resource.deploy_k8s in bootstrap.tf.
# ─────────────────────────────────────────────────────────────────────────────

# Uncomment the block below ONLY if you have set up an SSH tunnel and
# updated the Kubernetes provider to point to the tunneled endpoint.

# resource "kubernetes_namespace" "demo" {
#   metadata {
#     name = "demo"
#     labels = {
#       project = var.project_name
#     }
#   }
# }

# resource "kubernetes_config_map" "demo_config" {
#   metadata {
#     name      = "demo-config"
#     namespace = kubernetes_namespace.demo.metadata[0].name
#   }
#   data = {
#     APP_ENV = "production"
#     PROJECT = var.project_name
#   }
# }

# resource "kubernetes_deployment" "demo_app" {
#   metadata {
#     name      = "demo-app"
#     namespace = kubernetes_namespace.demo.metadata[0].name
#     labels = {
#       app = "demo-app"
#     }
#   }
#   spec {
#     replicas = 2
#     selector {
#       match_labels = { app = "demo-app" }
#     }
#     template {
#       metadata {
#         labels = { app = "demo-app" }
#       }
#       spec {
#         container {
#           name  = "nginx"
#           image = "nginx:1.27"
#           port { container_port = 80 }
#           resources {
#             requests = { cpu = "100m", memory = "128Mi" }
#             limits   = { cpu = "250m", memory = "256Mi" }
#           }
#           readiness_probe {
#             http_get { path = "/"; port = "80" }
#             initial_delay_seconds = 5
#             period_seconds        = 10
#             failure_threshold     = 3
#           }
#           liveness_probe {
#             http_get { path = "/"; port = "80" }
#             initial_delay_seconds = 15
#             period_seconds        = 20
#             failure_threshold     = 3
#           }
#         }
#       }
#     }
#   }
# }

# resource "kubernetes_service" "demo_app" {
#   metadata {
#     name      = "demo-app-svc"
#     namespace = kubernetes_namespace.demo.metadata[0].name
#   }
#   spec {
#     type     = "NodePort"
#     selector = { app = "demo-app" }
#     port {
#       port        = 80
#       target_port = 80
#       node_port   = var.node_port
#     }
#   }
# }
