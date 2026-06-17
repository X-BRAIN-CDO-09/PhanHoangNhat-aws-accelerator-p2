# EC2 Auto Scaling — ASG, Launch Template, Scaling Policies

> **Nguồn:** W10-D3 | **Chủ đề:** EC2 Auto Scaling

---

## 1. Auto Scaling là gì?

**Auto Scaling** tự động thêm/bớt EC2 instances dựa trên demand — đảm bảo **đúng capacity** tại mọi thời điểm.

```
       Traffic tăng → ASG thêm instances
       ┌──────┐  ┌──────┐  ┌──────┐  ┌──────┐
       │ EC2  │  │ EC2  │  │ EC2  │  │ EC2  │  ← Scale Out
       └──────┘  └──────┘  └──────┘  └──────┘
       
       Traffic giảm → ASG bớt instances
       ┌──────┐  ┌──────┐
       │ EC2  │  │ EC2  │                       ← Scale In
       └──────┘  └──────┘
```

### Tại sao cần Auto Scaling?

```
Không có Auto Scaling:
  ❌ Over-provision → Lãng phí tiền (24/7 chạy max capacity)
  ❌ Under-provision → Service chậm/down khi traffic tăng

Có Auto Scaling:
  ✅ Right-size tự động → Tiết kiệm 20-40% chi phí
  ✅ High availability → Tự replace unhealthy instances
  ✅ Predictable performance → Scale theo demand
```

---

## 2. Auto Scaling Group (ASG) — Các thành phần

```
Auto Scaling Group (ASG)
├── Launch Template          ← "Blueprint" cho EC2 instance
│   ├── AMI
│   ├── Instance Type
│   ├── Security Groups
│   ├── Key Pair
│   ├── User Data
│   └── IAM Instance Profile
│
├── Capacity Settings
│   ├── Min Size: 2          ← Tối thiểu 2 instances
│   ├── Max Size: 10         ← Tối đa 10 instances
│   └── Desired: 4           ← Mong muốn 4 instances
│
├── Scaling Policies         ← Khi nào scale
│   ├── Target Tracking
│   ├── Step Scaling
│   └── Scheduled
│
├── Health Check
│   ├── EC2 (default)
│   └── ELB (recommended)
│
└── Availability Zones
    ├── ap-southeast-1a
    ├── ap-southeast-1b
    └── ap-southeast-1c      ← Spread across AZs
```

---

## 3. Launch Template

```hcl
# launch_template.tf

resource "aws_launch_template" "app" {
  name_prefix   = "app-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.medium"
  
  # Security
  vpc_security_group_ids = [aws_security_group.app.id]
  key_name               = var.key_name
  
  # IAM Role
  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }
  
  # User Data (bootstrap script)
  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y docker
    systemctl start docker
    docker pull myapp:latest
    docker run -d -p 80:8080 myapp:latest
  EOF
  )
  
  # Monitoring
  monitoring {
    enabled = true  # Detailed monitoring (1 minute)
  }
  
  # Tags cho instances
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "app-${var.environment}"
      Environment = var.environment
    }
  }
  
  # EBS
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }
  
  lifecycle {
    create_before_destroy = true
  }
}
```

---

## 4. Auto Scaling Group — Terraform

```hcl
# asg.tf

resource "aws_autoscaling_group" "app" {
  name                = "app-asg-${var.environment}"
  vpc_zone_identifier = var.private_subnet_ids  # Multi-AZ
  
  # Capacity
  min_size         = 2
  max_size         = 10
  desired_capacity = 4
  
  # Launch Template
  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }
  
  # Health Check
  health_check_type         = "ELB"           # Recommend ELB check
  health_check_grace_period = 300             # 5 phút warm-up
  
  # Target Group (ALB)
  target_group_arns = [aws_lb_target_group.app.arn]
  
  # Instance refresh (rolling update)
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 75
    }
  }
  
  # Tags
  tag {
    key                 = "Name"
    value               = "app-${var.environment}"
    propagate_at_launch = true
  }
  
  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }
}
```

---

## 5. Scaling Policies

### 5.1 Target Tracking (Recommended)

ASG tự động điều chỉnh capacity để **giữ metric ở target value**:

```hcl
# Target Tracking: giữ CPU ở 60%
resource "aws_autoscaling_policy" "cpu_target" {
  name                   = "cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"
  
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60.0
    
    # Disable scale-in nếu muốn
    # disable_scale_in = true
  }
}

# Target Tracking: giữ request count per target ở 1000
resource "aws_autoscaling_policy" "request_target" {
  name                   = "request-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "TargetTrackingScaling"
  
  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "${aws_lb.main.arn_suffix}/${aws_lb_target_group.app.arn_suffix}"
    }
    target_value = 1000.0
  }
}
```

### Predefined Metrics:

| Metric | Mô tả | Target thường dùng |
|---|---|---|
| `ASGAverageCPUUtilization` | CPU trung bình | 50-70% |
| `ASGAverageNetworkIn` | Network bytes in | Tuỳ workload |
| `ASGAverageNetworkOut` | Network bytes out | Tuỳ workload |
| `ALBRequestCountPerTarget` | Requests per instance | 500-2000 |

### 5.2 Step Scaling

Scale theo **steps** — nhiều ngưỡng khác nhau:

```hcl
resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale-up"
  autoscaling_group_name = aws_autoscaling_group.app.name
  policy_type            = "StepScaling"
  adjustment_type        = "ChangeInCapacity"
  
  step_adjustment {
    scaling_adjustment          = 1    # +1 instance
    metric_interval_lower_bound = 0    # CPU 70-85%
    metric_interval_upper_bound = 15
  }
  
  step_adjustment {
    scaling_adjustment          = 3    # +3 instances
    metric_interval_lower_bound = 15   # CPU > 85%
  }
}

# CloudWatch Alarm trigger
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "cpu-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 70
  
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }
  
  alarm_actions = [aws_autoscaling_policy.scale_up.arn]
}
```

### 5.3 Scheduled Scaling

Scale theo lịch (biết trước traffic pattern):

```hcl
# Scale up vào giờ cao điểm (8:00 AM)
resource "aws_autoscaling_schedule" "morning_scale_up" {
  scheduled_action_name  = "morning-scale-up"
  autoscaling_group_name = aws_autoscaling_group.app.name
  
  min_size         = 4
  max_size         = 10
  desired_capacity = 6
  
  recurrence = "0 8 * * MON-FRI"  # 8:00 AM, Mon-Fri
}

# Scale down vào ban đêm (10:00 PM)
resource "aws_autoscaling_schedule" "night_scale_down" {
  scheduled_action_name  = "night-scale-down"
  autoscaling_group_name = aws_autoscaling_group.app.name
  
  min_size         = 2
  max_size         = 10
  desired_capacity = 2
  
  recurrence = "0 22 * * MON-FRI"  # 10:00 PM, Mon-Fri
}
```

---

## 6. Cooldown Period

**Cooldown** ngăn ASG scale quá nhanh (tránh oscillation):

```
Không có Cooldown:
  CPU 80% → +2 instances → CPU vẫn cao (chưa kịp warm up)
  → +2 instances nữa → CPU giảm → -4 instances → CPU lại cao
  → Oscillation! 😰

Có Cooldown (300s):
  CPU 80% → +2 instances → Đợi 5 phút
  → Instances warm up → CPU giảm về 50%
  → Stable! ✅
```

```hcl
resource "aws_autoscaling_policy" "cpu_target" {
  # ...
  target_tracking_configuration {
    # ...
    # Cooldown tự động quản lý bởi Target Tracking
  }
}

# Step Scaling cần set manual
resource "aws_autoscaling_group" "app" {
  # ...
  default_cooldown = 300  # 5 phút
}
```

---

## 7. Mixed Instances — On-Demand + Spot

```hcl
resource "aws_autoscaling_group" "app_mixed" {
  # ...
  
  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity                  = 2    # 2 On-Demand luôn chạy
      on_demand_percentage_above_base_capacity = 25   # 25% On-Demand, 75% Spot
      spot_allocation_strategy                 = "capacity-optimized"
    }
    
    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.app.id
        version            = "$Latest"
      }
      
      # Diversify instance types cho Spot
      override {
        instance_type = "t3.medium"
      }
      override {
        instance_type = "t3a.medium"
      }
      override {
        instance_type = "m5.large"
      }
    }
  }
}
```

---

## 🔗 Tài liệu tham khảo

- [EC2 Auto Scaling Guide](https://docs.aws.amazon.com/autoscaling/ec2/userguide) ⭐⭐⭐
- [Target Tracking Policies](https://docs.aws.amazon.com/autoscaling/ec2/userguide/as-scaling-target-tracking.html) ⭐⭐⭐
- [Mixed Instances](https://docs.aws.amazon.com/autoscaling/ec2/userguide/ec2-auto-scaling-mixed-instances-groups.html) ⭐⭐
