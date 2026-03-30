variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "your_ip" {
  description = "Your public IP address in CIDR notation (e.g. 1.2.3.4/32). Only this IP will be allowed to reach the ALB."
  type        = string
  default     = "66.30.229.28/32"
}

variable "project" {
  description = "Short name prefix applied to all resources"
  type        = string
  default     = "ecs-init-poc"
}
