# =============================================================================
# FILE: modules/ecr/outputs.tf
# PURPOSE: Exposes the ECR repository URLs and ARNs so other parts of the
#          infrastructure (ECS tasks, CI/CD pipelines) can reference them.
#
# KEY CONCEPTS:
#   - Repository URL: the address you use to push/pull Docker images.
#     Looks like: 123456789012.dkr.ecr.eu-west-2.amazonaws.com/multi-tier-frontend
#     You'll use this in: docker push, docker pull, ECS task definitions.
#
#   - Repository ARN: Amazon Resource Name — a unique identifier for the
#     repository across ALL of AWS. Used in IAM policies to grant permissions.
#     Looks like: arn:aws:ecr:eu-west-2:123456789012:repository/multi-tier-frontend
# =============================================================================

# -----------------------------------------------------------------------------
# REPOSITORY URLs (as a map)
# -----------------------------------------------------------------------------
# Returns a map like:
#   {
#     "multi-tier-frontend" = "123456789012.dkr.ecr.eu-west-2.amazonaws.com/multi-tier-frontend"
#     "multi-tier-backend"  = "123456789012.dkr.ecr.eu-west-2.amazonaws.com/multi-tier-backend"
#   }
#
# The "for" expression loops over all repositories created by for_each and
# builds a map of name => url. This is more useful than a list because you
# can look up a specific repo by name: module.ecr.repository_urls["multi-tier-frontend"]
output "repository_urls" {
  description = "Map of repository names to their URLs (used for docker push/pull)"
  value = {
    for name, repo in aws_ecr_repository.repos : name => repo.repository_url
  }
}

# -----------------------------------------------------------------------------
# REPOSITORY ARNs (as a map)
# -----------------------------------------------------------------------------
# Returns a map like:
#   {
#     "multi-tier-frontend" = "arn:aws:ecr:eu-west-2:123456789012:repository/multi-tier-frontend"
#     "multi-tier-backend"  = "arn:aws:ecr:eu-west-2:123456789012:repository/multi-tier-backend"
#   }
#
# You'll need these ARNs when writing IAM policies to grant ECS tasks (or CI/CD
# pipelines) permission to pull images from these specific repositories.
output "repository_arns" {
  description = "Map of repository names to their ARNs (used in IAM policies)"
  value = {
    for name, repo in aws_ecr_repository.repos : name => repo.arn
  }
}
