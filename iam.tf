data "aws_iam_policy_document" "ecs_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# ─── Execution Role ────────────────────────────────────────────────────────────
# Used by the ECS agent to pull container images and write CloudWatch logs.

resource "aws_iam_role" "execution" {
  name               = "${var.project}-execution-role-${random_id.suffix.hex}"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = {
    Project = var.project
  }
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ─── Task Role ─────────────────────────────────────────────────────────────────
# Used by the running containers (specifically the init container) to read from S3.

resource "aws_iam_role" "task" {
  name               = "${var.project}-task-role-${random_id.suffix.hex}"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role.json

  tags = {
    Project = var.project
  }
}

data "aws_iam_policy_document" "task_s3_read" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.content.arn}/*"]
  }

  statement {
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.content.arn]
  }
}

resource "aws_iam_role_policy" "task_s3_read" {
  name   = "s3-read-content"
  role   = aws_iam_role.task.id
  policy = data.aws_iam_policy_document.task_s3_read.json
}
