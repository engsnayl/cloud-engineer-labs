variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "eu-west-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must be a valid AWS region identifier (e.g. eu-west-1)."
  }
}

variable "project_name" {
  description = "Project identifier used in resource names and tags"
  type        = string
  default     = "multi-tier-app"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name)) && length(var.project_name) <= 30
    error_message = "project_name must be lowercase alphanumeric with hyphens, max 30 characters."
  }
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid CIDR block (e.g. 10.0.0.0/16)."
  }
}

variable "availability_zones" {
  description = "AZs to deploy into. Must be in the configured region."
  type        = list(string)
  default     = ["eu-west-1a", "eu-west-1b"]

  validation {
    condition     = length(var.availability_zones) >= 2
    error_message = "At least 2 availability zones are required for multi-AZ deployment."
  }
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ, same order)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ, same order)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

variable "ecr_repository_names" {
  description = "Names of the ECR repositories to create"
  type        = list(string)
  default     = ["multi-tier-frontend", "multi-tier-backend"]
}
