output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer. Open http://<value> in your browser."
  value       = "http://${aws_lb.main.dns_name}"
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket holding the static HTML content"
  value       = aws_s3_bucket.content.id
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.app.name
}
