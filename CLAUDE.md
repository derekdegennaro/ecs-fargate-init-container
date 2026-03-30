# ECS Fargate Init Container POC

## Goal

Prove that an ECS Fargate service can run an init container to completion before the main application container starts. The init container downloads static HTML from S3 into a shared ephemeral volume; nginx then serves that content. Access is restricted to a single public IP via an ALB.

**Why:** POC to validate ECS container dependency ordering using `dependsOn` + `condition: SUCCESS` before using this pattern in production.

**How to apply:** Use this as the reference design when extending or debugging the repo.

---

## Architecture

```
Internet (port 80, from X.X.X.X/32 only)
  ▼
ALB (public subnets, application load balancer)
  ▼
ECS Fargate Task (public subnets, assign_public_ip=true)
  ├── init container  (amazon/aws-cli:latest, essential=false)
  │     └── aws s3 cp s3://<bucket>/index.html /usr/share/nginx/html/index.html
  │          → writes to shared ephemeral volume, exits 0
  └── nginx container (nginx:alpine, essential=true)
        └── dependsOn: init SUCCESS → serves /usr/share/nginx/html/
```

---

## Key ECS Mechanics Demonstrated

- `essential = false` on the init container — task stays alive after it exits
- `dependsOn = [{containerName = "init", condition = "SUCCESS"}]` on nginx — ECS will not start nginx until init exits with code 0
- Shared Fargate ephemeral bind-mount volume (`html-content`) — no EFS required; mounted at `/usr/share/nginx/html` in both containers

---

## File Structure

| File | Contents |
|------|----------|
| `main.tf` | AWS + Random providers, AZ data source |
| `variables.tf` | `aws_region`, `project` |
| `vpc.tf` | VPC `10.0.0.0/16`, 2 public subnets, IGW, route table |
| `s3.tf` | Private S3 bucket (random suffix), `index.html` object |
| `iam.tf` | Execution role (AmazonECSTaskExecutionRolePolicy) + Task role (s3:GetObject on content bucket) |
| `ecs.tf` | CloudWatch log groups, ALB SG, Task SG, ECS cluster, task definition, ALB + target group + listener, ECS service |
| `outputs.tf` | `alb_dns_name`, `s3_bucket_name`, `ecs_cluster_name`, `ecs_service_name` |

---

## IAM Design

Two distinct roles (do not conflate):
- **Execution role** — used by ECS agent to pull images from ECR and write CloudWatch logs
- **Task role** — used by running containers (init) to call `s3:GetObject` and `s3:ListBucket` on the content bucket

---

## Networking

- Tasks run in public subnets with `assign_public_ip = true` (no NAT Gateway — acceptable for POC)
- ALB SG: ingress port 80 from `66.30.229.28/32` only
- Task SG: ingress port 80 from ALB SG only; egress all (needed for S3 and ECR public endpoint access)

---

## Verification Steps

1. `terraform init && terraform apply`
2. Open `http://<alb_dns_name>` — should display the success page served by nginx from S3 content
3. ECS console → task history: confirm "init" container exited code 0 before nginx started
4. From a different IP: ALB should return 403 (IP restriction working)
5. CloudWatch log groups: `/ecs/ecs-init-poc/init` and `/ecs/ecs-init-poc/nginx`

---

## Deployment Notes

- Bucket name is randomized via `random_id.suffix.hex` to avoid global naming conflicts
- `force_destroy = true` on the S3 bucket so `terraform destroy` works cleanly
- ALB takes ~2–3 min to provision; task startup adds another ~60–90s (init runs first, then nginx)
- Caller's public IP is resolved automatically at plan time via `data "http" "my_ip"` (calls `checkip.amazonaws.com`); no manual IP variable needed
