output "repository_urls" {
  description = "Map of repository name : repository URL (for docker push targets)"
  value       = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
}

output "repository_arns" {
  description = "Map of repository name :ARN (for IAM policy resource fields)"
  value       = { for name, repo in aws_ecr_repository.this : name => repo.arn }
}

output "registry_id" {
  description = "AWS account ID hosting these repositories (same for all)"
  value       = values(aws_ecr_repository.this)[0].registry_id
}
