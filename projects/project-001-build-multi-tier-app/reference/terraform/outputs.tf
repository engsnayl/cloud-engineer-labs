# =============================================================================
# FILE: terraform/outputs.tf
# PURPOSE: Exposes key resource IDs and URLs from the root module.
#
# WHY ROOT-LEVEL OUTPUTS?
#   When you run "terraform apply", these outputs are printed to the screen.
#   They give you the important IDs and URLs you need for:
#   - Configuring your CI/CD pipeline (ECR URLs for docker push)
#   - Debugging in the AWS Console (looking up resources by ID)
#   - Passing values to other tools (kubectl, Docker, scripts)
#
# You can also retrieve them later with: terraform output
# Or a specific one: terraform output vpc_id
# =============================================================================

# -----------------------------------------------------------------------------
# VPC OUTPUTS
# -----------------------------------------------------------------------------

# The VPC ID — you'll need this when creating any resource inside the VPC.
output "vpc_id" {
  description = "The ID of the VPC"
  value       = module.vpc.vpc_id
}

# List of public subnet IDs — used for load balancers, bastion hosts.
output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

# List of private subnet IDs — used for backend services, databases.
output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = module.vpc.private_subnet_ids
}

# -----------------------------------------------------------------------------
# ECR OUTPUTS
# -----------------------------------------------------------------------------

# Map of ECR repository URLs — you need these to push Docker images.
# Example usage:
#   docker tag my-frontend:latest <ecr_url>/multi-tier-frontend:latest
#   docker push <ecr_url>/multi-tier-frontend:latest
output "ecr_repository_urls" {
  description = "Map of ECR repository names to their URLs (for docker push/pull)"
  value       = module.ecr.repository_urls
}

# -----------------------------------------------------------------------------
# SECURITY GROUP OUTPUTS
# -----------------------------------------------------------------------------
# These IDs are needed when launching ECS tasks, EC2 instances, or RDS
# databases — you attach the appropriate security group to each resource.

output "frontend_sg_id" {
  description = "Security Group ID for the frontend service"
  value       = aws_security_group.frontend.id
}

output "backend_sg_id" {
  description = "Security Group ID for the backend API service"
  value       = aws_security_group.backend.id
}

output "database_sg_id" {
  description = "Security Group ID for the database"
  value       = aws_security_group.database.id
}
