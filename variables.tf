variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Short name prefix applied to all resources"
  type        = string
  default     = "ecs-init-poc"
}
