# ─── CloudWatch Log Groups ────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "init" {
  name              = "/ecs/${var.project}/init"
  retention_in_days = 7

  tags = {
    Project = var.project
  }
}

resource "aws_cloudwatch_log_group" "nginx" {
  name              = "/ecs/${var.project}/nginx"
  retention_in_days = 7

  tags = {
    Project = var.project
  }
}

# ─── Security Groups ──────────────────────────────────────────────────────────

resource "aws_security_group" "alb" {
  name        = "${var.project}-alb-sg"
  description = "Allow HTTP from your IP only"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from your IP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.your_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project}-alb-sg"
    Project = var.project
  }
}

resource "aws_security_group" "task" {
  name        = "${var.project}-task-sg"
  description = "Allow HTTP from ALB; allow all egress (S3, ECR)"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project}-task-sg"
    Project = var.project
  }
}

# ─── ECS Cluster ──────────────────────────────────────────────────────────────

resource "aws_ecs_cluster" "main" {
  name = "${var.project}-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  tags = {
    Project = var.project
  }
}

# ─── Task Definition ──────────────────────────────────────────────────────────

resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project}-task"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task.arn

  # Shared ephemeral volume — no host or EFS config needed for Fargate bind-mount
  volume {
    name = "html-content"
  }

  container_definitions = jsonencode([
    {
      # ── Init container ──────────────────────────────────────────────────────
      # Downloads the static HTML from S3 into the shared volume, then exits.
      # essential = false so the task keeps running after this container exits.
      name      = "init"
      image     = "amazon/aws-cli:latest"
      essential = false

      command = [
        "s3", "cp",
        "s3://${aws_s3_bucket.content.id}/index.html",
        "/usr/share/nginx/html/index.html"
      ]

      mountPoints = [
        {
          sourceVolume  = "html-content"
          containerPath = "/usr/share/nginx/html"
          readOnly      = false
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.init.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "init"
        }
      }
    },
    {
      # ── Nginx container ─────────────────────────────────────────────────────
      # Starts only after the init container exits with code 0 (SUCCESS).
      # Serves the index.html that the init container placed in the volume.
      name      = "nginx"
      image     = "nginx:alpine"
      essential = true

      portMappings = [
        {
          containerPort = 80
          protocol      = "tcp"
        }
      ]

      # This is the key directive that proves the init-container pattern
      dependsOn = [
        {
          containerName = "init"
          condition     = "SUCCESS"
        }
      ]

      mountPoints = [
        {
          sourceVolume  = "html-content"
          containerPath = "/usr/share/nginx/html"
          readOnly      = true
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.nginx.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "nginx"
        }
      }
    }
  ])

  tags = {
    Project = var.project
  }
}

# ─── Application Load Balancer ───────────────────────────────────────────────

resource "aws_lb" "main" {
  name               = "${var.project}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Project = var.project
  }
}

resource "aws_lb_target_group" "nginx" {
  name        = "${var.project}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200"
  }

  tags = {
    Project = var.project
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nginx.arn
  }
}

# ─── ECS Service ─────────────────────────────────────────────────────────────

resource "aws_ecs_service" "app" {
  name            = "${var.project}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.nginx.arn
    container_name   = "nginx"
    container_port   = 80
  }

  depends_on = [
    aws_lb_listener.http,
    aws_iam_role_policy_attachment.execution
  ]

  tags = {
    Project = var.project
  }
}
