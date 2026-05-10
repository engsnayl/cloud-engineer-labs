output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (one per AZ)"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs (one per AZ)"
  value       = module.vpc.private_subnet_ids
}

output "frontend_sg_id" {
  description = "Frontend tier security group ID"
  value       = module.security.frontend_sg_id
}

output "backend_sg_id" {
  description = "Backend tier security group ID"
  value       = module.security.backend_sg_id
}

output "database_sg_id" {
  description = "Database tier security group ID"
  value       = module.security.database_sg_id
}

output "ecr_repository_urls" {
  description = "ECR repository URLs (map: name -> URL)"
  value       = module.ecr.repository_urls
}

output "ecr_repository_arns" {
  description = "ECR repository ARNs (map: name -> ARN)"
  value       = module.ecr.repository_arns
}

output "ecr_registry_id" {
  description = "ECR registry ID (AWS account hosting the registry)"
  value       = module.ecr.registry_id
}
