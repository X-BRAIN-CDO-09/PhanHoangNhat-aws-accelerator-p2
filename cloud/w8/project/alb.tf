# =============================================================================
# alb.tf — Application Load Balancer, Target Group, Listener, and Attachment
#
# Flow:
#   Internet → ALB:80 → Target Group → EC2:30080 (NodePort)
#
# NOTE: Target Group Attachment depends on bootstrap.tf null_resource
# to ensure Kubernetes is running before traffic is routed.
# =============================================================================

# ── Application Load Balancer ─────────────────────────────────────────────────
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = local.subnet_ids

  # Enable access logs for production use; disabled for demo simplicity
  enable_deletion_protection = false

  tags = {
    Name = "${var.project_name}-alb"
  }
}

# ── Target Group ──────────────────────────────────────────────────────────────
resource "aws_lb_target_group" "app" {
  name     = "${var.project_name}-tg"
  port     = var.node_port
  protocol = "HTTP"
  vpc_id   = local.vpc_id

  # Health check against nginx default path
  health_check {
    enabled             = true
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = {
    Name = "${var.project_name}-tg"
  }
}

# ── HTTP Listener on port 80 ──────────────────────────────────────────────────
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ── Target Group Attachment ───────────────────────────────────────────────────
# Attach the EC2 instance to the Target Group at the NodePort.
# depends_on: bootstrap must complete first so app is actually running.
resource "aws_lb_target_group_attachment" "app" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.k8s_host.id
  port             = var.node_port

  depends_on = [null_resource.build_and_deploy]
}
