output "zone_id" {
  description = "The ID of the Route 53 hosted zone"
  value       = aws_route53_zone.main.zone_id
}

output "health_check_id" {
  description = "The ID of the Route 53 health check monitoring the primary endpoint"
  value       = aws_route53_health_check.primary.id
}
