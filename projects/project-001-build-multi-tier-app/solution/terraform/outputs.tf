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

output "secrets_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret. For audit and operator reference."
  value       = module.secrets.secret_arn
}

output "secrets_secret_name" {
  description = "Name of the AWS Secrets Manager secret. Referenced by the ExternalSecret manifest's remoteRef.key."
  value       = module.secrets.secret_name
}

output "secrets_iam_user_name" {
  description = "Name of the IAM user External Secrets Operator authenticates as."
  value       = module.secrets.iam_user_name
}

output "secrets_access_key_id" {
  description = "Access key ID for the ESO IAM user. Bootstrap into the cluster via the aws-creds K8s Secret. Not sensitive — IDs identify but do not grant access."
  value       = module.secrets.access_key_id
}

output "secrets_access_key_secret" {
  description = "Secret access key for the ESO IAM user. Bootstrap into the cluster via the aws-creds K8s Secret. SENSITIVE — also stored in plain text in the Terraform state file."
  value       = module.secrets.access_key_secret
  sensitive   = true
}
