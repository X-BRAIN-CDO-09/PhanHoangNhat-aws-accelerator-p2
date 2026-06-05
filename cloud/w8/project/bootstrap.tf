# =============================================================================
# bootstrap.tf — EC2 bootstrap orchestration via SSH remote-exec
#
# DESIGN: Single null_resource thay vì 2 resource riêng biệt.
#
# Thay vì polling sentinel file (Attempt X/240 mỗi 5s), dùng:
#   cloud-init status --wait
# → built-in Ubuntu mechanism, block cho đến khi user_data hoàn thành.
# → Không có vòng lặp thủ công, không có timeout tự đặt.
# → Nếu user_data fail → cloud-init trả về lỗi ngay, không chờ 20 phút.
#
# Flow (một SSH session duy nhất):
#   1. cloud-init status --wait   (chờ user_data xong: Docker + kind)
#   2. mkdir /tmp/app-build
#   3. Upload app/Dockerfile      (file provisioner)
#   4. Upload app/index.html      (file provisioner)
#   5. docker build -t demo-app:latest
#   6. kind load docker-image     (không cần registry)
#   7. Upload K8s manifests       (file provisioner)
#   8. kubectl apply + rollout status
#     → aws_lb_target_group_attachment.app
# =============================================================================

resource "null_resource" "build_and_deploy" {
  triggers = {
    instance_id   = aws_instance.k8s_host.id
    # Re-deploy khi app source thay đổi (không cần recreate EC2)
    app_hash      = sha256(join("", [
      filesha256("${path.module}/app/Dockerfile"),
      filesha256("${path.module}/app/index.html"),
    ]))
    manifest_hash = sha256("${var.project_name}-${tostring(var.node_port)}")
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    host        = aws_instance.k8s_host.public_ip
    private_key = tls_private_key.ec2.private_key_pem
    timeout     = "15m"
  }

  # ── Step 1: Chờ user_data hoàn thành via cloud-init ───────────────────────
  # cloud-init status --wait trả về 0 ngay cả khi script lỗi ở một số phiên bản.
  # → Kiểm tra tường minh: status phải là "done", không phải "error"/"degraded".
  provisioner "remote-exec" {
    inline = [
      "echo '=== Waiting for cloud-init (user_data) to complete ==='",
      "cloud-init status --wait || true",
      "CLOUD_STATUS=$(cloud-init status | grep '^status:' | awk '{print $2}')",
      "echo \"Cloud-init status: $CLOUD_STATUS\"",
      "if [ \"$CLOUD_STATUS\" = 'error' ] || [ \"$CLOUD_STATUS\" = 'degraded' ]; then echo '=== user_data FAILED. Log:'; tail -80 /var/log/user-data.log || true; exit 1; fi",
      "echo '=== user_data OK! Cluster nodes:'",
      "export KUBECONFIG=/home/ubuntu/.kube/config",
      "kubectl get nodes",
    ]
  }

  # ── Step 2: Tạo build directory ────────────────────────────────────────────
  provisioner "remote-exec" {
    inline = ["mkdir -p /tmp/app-build"]
  }

  # ── Step 3: Upload app source files ────────────────────────────────────────
  provisioner "file" {
    source      = "${path.module}/app/Dockerfile"
    destination = "/tmp/app-build/Dockerfile"
  }

  provisioner "file" {
    source      = "${path.module}/app/index.html"
    destination = "/tmp/app-build/index.html"
  }

  # ── Step 4: Build Docker image trên EC2 + load vào kind ────────────────────
  provisioner "remote-exec" {
    inline = [
      "echo '=== Building Docker image on EC2 ==='",
      "docker build -t demo-app:latest /tmp/app-build/",
      "docker images demo-app",
      "echo '=== Loading image into kind (no registry needed) ==='",
      "kind load docker-image demo-app:latest --name ${var.cluster_name}",
    ]
  }

  # ── Step 5: Upload K8s manifests ───────────────────────────────────────────
  provisioner "file" {
    content = templatefile("${path.module}/templates/k8s-manifests.yaml.tpl", {
      project_name = var.project_name
      node_port    = var.node_port
    })
    destination = "/tmp/k8s-manifests.yaml"
  }

  # ── Step 6: Deploy to Kubernetes ───────────────────────────────────────────
  provisioner "remote-exec" {
    inline = [
      "echo '=== Deploying to Kubernetes ==='",
      "export KUBECONFIG=/home/ubuntu/.kube/config",
      "kubectl apply -f /tmp/k8s-manifests.yaml",
      "kubectl rollout status deployment/demo-app -n demo --timeout=120s",
      "kubectl get all -n demo",
      "echo '=== Deployment complete ==='"
    ]
  }

  depends_on = [aws_instance.k8s_host]
}
