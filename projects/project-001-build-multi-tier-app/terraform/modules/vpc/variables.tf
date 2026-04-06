# =============================================================================
# FILE: modules/vpc/variables.tf
# PURPOSE: Defines the input variables for the VPC module.
#
# WHAT ARE VARIABLES?
#   Variables make your Terraform code reusable. Instead of hardcoding values
#   like "10.0.0.0/16" directly in main.tf, we use variables so the same
#   module can be used with different values for different environments
#   (dev, staging, production) or different projects.
#
# HOW VARIABLES WORK:
#   1. You DECLARE them here (name, type, description, optional default)
#   2. You USE them in main.tf as var.variable_name
#   3. You PASS values in when calling the module (from the root module)
#
# If a variable has a "default", it's optional — you don't have to pass it.
# If there's no default, Terraform will ask you for the value (or error out).
# =============================================================================

# -----------------------------------------------------------------------------
# VPC CIDR BLOCK
# -----------------------------------------------------------------------------
# The overall IP address range for the entire VPC.
# /16 gives 65,536 addresses — plenty for a learning project.
# In production, you'd plan this carefully to avoid overlaps with other VPCs
# if you ever need to connect them (VPC peering).
variable "vpc_cidr" {
  description = "The CIDR block for the VPC (e.g., 10.0.0.0/16)"
  type        = string       # A simple text value
  default     = "10.0.0.0/16" # Sensible default — change if you need a different range
}

# -----------------------------------------------------------------------------
# PUBLIC SUBNET CIDRs
# -----------------------------------------------------------------------------
# A list of CIDR blocks, one for each public subnet we want to create.
# We use a list so we can create multiple subnets with count in main.tf.
# Each /24 gives us 256 addresses (actually 251 usable — AWS reserves 5).
variable "public_subnet_cidrs" {
  description = "List of CIDR blocks for public subnets (one per AZ)"
  type        = list(string) # A list of text values, e.g., ["10.0.1.0/24", "10.0.2.0/24"]
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

# -----------------------------------------------------------------------------
# PRIVATE SUBNET CIDRs
# -----------------------------------------------------------------------------
# Same idea as public, but for private subnets.
# We use 10.0.10.0/24 and 10.0.20.0/24 — the gap in numbering makes it easy
# to tell public (1, 2) from private (10, 20) at a glance.
variable "private_subnet_cidrs" {
  description = "List of CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

# -----------------------------------------------------------------------------
# AVAILABILITY ZONES
# -----------------------------------------------------------------------------
# Which AWS Availability Zones to use. We spread subnets across AZs for
# high availability. eu-west-2 (London) has 3 AZs: a, b, and c.
# We use 2 for our learning project — that's enough for redundancy.
variable "availability_zones" {
  description = "List of AWS Availability Zones to deploy into"
  type        = list(string)
  default     = ["eu-west-2a", "eu-west-2b"]
}

# -----------------------------------------------------------------------------
# PROJECT NAME
# -----------------------------------------------------------------------------
# Used in resource tags and Name fields. Helps you identify which project
# a resource belongs to when you have multiple projects in one AWS account.
variable "project_name" {
  description = "Name of the project — used for tagging and naming resources"
  type        = string
  default     = "multi-tier-app"
}

# -----------------------------------------------------------------------------
# ENVIRONMENT
# -----------------------------------------------------------------------------
# Tracks which environment this is: development, staging, or production.
# Useful for cost tracking and to avoid accidentally deleting production resources.
variable "environment" {
  description = "Deployment environment (e.g., development, staging, production)"
  type        = string
  default     = "development"
}
