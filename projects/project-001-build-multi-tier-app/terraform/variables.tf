# =============================================================================
# FILE: terraform/variables.tf
# PURPOSE: Defines the input variables for the ROOT module (this directory).
#
# ROOT MODULE vs CHILD MODULES:
#   - Child modules (like modules/vpc/) have their own variables.tf
#   - This file is for the ROOT module — the top-level configuration
#   - Values can be set via:
#     1. terraform.tfvars file (most common)
#     2. Command line: terraform apply -var="environment=production"
#     3. Environment variables: TF_VAR_environment=production
#     4. Default values (defined below)
#
# VARIABLE PRECEDENCE (highest to lowest):
#   1. -var flag on command line
#   2. terraform.tfvars or *.auto.tfvars files
#   3. TF_VAR_ environment variables
#   4. Default values in this file
#   5. Interactive prompt (if no default and no value provided)
# =============================================================================

# -----------------------------------------------------------------------------
# AWS REGION
# -----------------------------------------------------------------------------
# Which AWS region to deploy all resources into.
# eu-west-2 is the London region — chosen for low latency if you're in the UK.
# All resources (VPC, ECR, Security Groups, etc.) will be created here.
#
# IMPORTANT: Changing the region after deployment means Terraform will
# DESTROY everything in the old region and recreate it in the new one.
# This is a destructive change — be careful!
variable "aws_region" {
  description = "AWS region to deploy resources into"
  type        = string
  default     = "eu-west-2" # London
}

# -----------------------------------------------------------------------------
# PROJECT NAME
# -----------------------------------------------------------------------------
# A human-readable name for the project. Used in:
# - Resource names (e.g., "multi-tier-app-vpc", "multi-tier-app-frontend-sg")
# - Tags (for cost tracking, filtering in AWS Console)
# - S3 bucket names (if used for state storage)
#
# Keep it short, lowercase, with hyphens. No spaces or special characters.
variable "project_name" {
  description = "Name of the project — used in resource names and tags"
  type        = string
  default     = "multi-tier-app"
}

# -----------------------------------------------------------------------------
# ENVIRONMENT
# -----------------------------------------------------------------------------
# Which environment this deployment is for. Common values:
#   - "development"  — your personal dev/learning environment
#   - "staging"      — pre-production testing
#   - "production"   — live, user-facing
#
# This value appears in tags so you can:
# - Filter resources by environment in the AWS Console
# - Set up cost alerts per environment
# - Ensure you don't accidentally delete production resources
variable "environment" {
  description = "Deployment environment (development, staging, production)"
  type        = string
  default     = "development"
}
