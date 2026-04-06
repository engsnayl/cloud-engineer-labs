# =============================================================================
# FILE: modules/ecr/variables.tf
# PURPOSE: Defines the input variables for the ECR module.
#
# This module is designed to be flexible — you pass in a list of repository
# names and it creates one ECR repository per name. This means you can reuse
# the same module if you add more services later (e.g., a worker, an API
# gateway, etc.) without changing the module code.
# =============================================================================

# -----------------------------------------------------------------------------
# REPOSITORY NAMES
# -----------------------------------------------------------------------------
# A list of names for the ECR repositories to create.
# Each name becomes a separate Docker image repository in ECR.
# Convention: use lowercase with hyphens (e.g., "multi-tier-frontend").
variable "repository_names" {
  description = "List of ECR repository names to create (one per microservice)"
  type        = list(string)
  default     = ["multi-tier-frontend", "multi-tier-backend"]
}

# -----------------------------------------------------------------------------
# PROJECT NAME
# -----------------------------------------------------------------------------
# Used in tags to identify which project these repositories belong to.
variable "project_name" {
  description = "Name of the project — used for tagging resources"
  type        = string
  default     = "multi-tier-app"
}

# -----------------------------------------------------------------------------
# ENVIRONMENT
# -----------------------------------------------------------------------------
# Tracks the deployment environment. Useful for cost allocation and to
# prevent accidental deletion of production repositories.
variable "environment" {
  description = "Deployment environment (e.g., development, staging, production)"
  type        = string
  default     = "development"
}
