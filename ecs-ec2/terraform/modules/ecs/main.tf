data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_ecs_cluster" "this" {
  name = "${var.name}-cluster"
  tags = var.tags
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# ---------------- IAM ----------------
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Container-instance role: lets the ECS agent register the host with the cluster.
resource "aws_iam_role" "instance" {
  name               = "${var.name}-instance"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "instance_ecs" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

# SSM Session Manager: shell access without SSH keys or open port 22.
resource "aws_iam_role_policy_attachment" "instance_ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.name}-instance"
  role = aws_iam_role.instance.name
}

# Task execution role: pull from ECR + write logs. Task role: app's own permissions (none needed).
resource "aws_iam_role" "execution" {
  name               = "${var.name}-task-execution"
  assume_role_policy = data.aws_iam_policy_document.tasks_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  name               = "${var.name}-task"
  assume_role_policy = data.aws_iam_policy_document.tasks_assume.json
  tags               = var.tags
}

# ---------------- Instances: security group, launch template, ASG ----------------
resource "aws_security_group" "instances" {
  name_prefix = "${var.name}-ec2-"
  description = "ECS container instances: dynamic host ports from ALB only"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-ec2-sg" })

  ingress {
    description     = "Docker ephemeral host ports from ALB"
    from_port       = 32768
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }
  egress {
    description = "Outbound (ECR, CloudWatch, ECS API) via NAT"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  lifecycle { create_before_destroy = true }
}

resource "aws_launch_template" "this" {
  name_prefix            = "${var.name}-"
  image_id               = data.aws_ssm_parameter.ecs_ami.value
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.instances.id]

  iam_instance_profile { name = aws_iam_instance_profile.instance.name }

  user_data = base64encode(<<-EOT
    #!/bin/bash
    cat <<'CFG' >> /etc/ecs/ecs.config
    ECS_CLUSTER=${aws_ecs_cluster.this.name}
    ECS_ENABLE_CONTAINER_METADATA=true
    ECS_ENABLE_TASK_IAM_ROLE=true
    CFG
  EOT
  )

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 2
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = 30
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  monitoring { enabled = true }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, { Name = "${var.name}-ecs-instance" })
  }
  lifecycle { create_before_destroy = true }
}

resource "aws_autoscaling_group" "this" {
  name_prefix           = "${var.name}-asg-"
  min_size              = var.asg_min
  max_size              = var.asg_max
  desired_capacity      = var.asg_min
  vpc_zone_identifier   = var.private_subnet_ids
  health_check_type     = "EC2"
  protect_from_scale_in = true # required for ECS managed termination protection

  launch_template {
    id      = aws_launch_template.this.id
    version = aws_launch_template.this.latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences { min_healthy_percentage = 50 }
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }

  lifecycle { ignore_changes = [desired_capacity] } # owned by the capacity provider
}

# Capacity provider: ECS scales the ASG to fit the tasks that need placing.
resource "aws_ecs_capacity_provider" "this" {
  name = "${var.name}-ec2"
  tags = var.tags

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.this.arn
    managed_termination_protection = "ENABLED"
    managed_scaling {
      status                    = "ENABLED"
      target_capacity           = 80
      minimum_scaling_step_size = 1
      maximum_scaling_step_size = 2
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
  capacity_providers = [aws_ecs_capacity_provider.this.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.this.name
    weight            = 1
  }
}

# ---------------- Task definition & service ----------------
resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["EC2"]
  network_mode             = "bridge" # Docker bridge + dynamic host ports (hostPort = 0)
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn
  tags                     = var.tags

  container_definitions = jsonencode([{
    name              = "app"
    image             = var.image
    essential         = true
    cpu               = var.container_cpu
    memory            = var.container_memory
    portMappings      = [{ containerPort = var.container_port, hostPort = 0, protocol = "tcp" }]
    environment       = [for k, v in var.environment_variables : { name = k, value = v }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.app.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "app"
      }
    }
  }])
}

resource "aws_ecs_service" "this" {
  name                               = "${var.name}-svc"
  cluster                            = aws_ecs_cluster.this.id
  task_definition                    = aws_ecs_task_definition.this.arn
  desired_count                      = var.desired_count
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 30
  tags                               = var.tags

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.this.name
    weight            = 1
  }

  # Spread tasks across AZs first, then across instances.
  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }
  ordered_placement_strategy {
    type  = "spread"
    field = "instanceId"
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "app"
    container_port   = var.container_port
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  lifecycle { ignore_changes = [desired_count] } # owned by service autoscaling
  depends_on = [aws_ecs_cluster_capacity_providers.this]
}

# Service autoscaling (tasks) on top of capacity-provider scaling (instances).
resource "aws_appautoscaling_target" "this" {
  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${aws_ecs_service.this.name}"
  min_capacity       = var.min_tasks
  max_capacity       = var.max_tasks
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${var.name}-cpu-target"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this.service_namespace
  scalable_dimension = aws_appautoscaling_target.this.scalable_dimension
  resource_id        = aws_appautoscaling_target.this.resource_id

  target_tracking_scaling_policy_configuration {
    target_value = var.cpu_target_percent
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}
