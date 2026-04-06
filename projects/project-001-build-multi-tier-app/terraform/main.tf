# =============================================================================
# FILE: terraform/main.tf
# PURPOSE: The ROOT MODULE — the entry point for your entire infrastructure.
#          This file ties together all the child modules (VPC, ECR) and creates
#          resources that span multiple modules (like Security Groups).
#
# HOW TERRAFORM WORKS:
#   1. You write .tf files describing the infrastructure you WANT
#   2. "terraform plan" shows what Terraform WILL do (create, change, destroy)
#   3. "terraform apply" makes it happen in AWS
#   4. "terraform destroy" tears it ALL down
#
# =============================================================================
#
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# !! COST WARNING — READ THIS !!
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
# !!                                                                         !!
# !!  This configuration creates AWS resources that COST MONEY.              !!
# !!  The NAT Gateway alone costs ~$32/month even if idle.                   !!
# !!                                                                         !!
# !!  ALWAYS run "terraform destroy" when you're done learning/testing       !!
# !!  to avoid surprise charges on your AWS bill.                            !!
# !!                                                                         !!
# !!  To destroy everything:                                                 !!
# !!    cd terraform/                                                        !!
# !!    terraform destroy                                                    !!
# !!                                                                         !!
# !!  Terraform will show you what it plans to delete — type "yes" to        !!
# !!  confirm. Double-check in the AWS Console afterwards that nothing       !!
# !!  was left behind.                                                       !!
# !!                                                                         !!
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#
# =============================================================================

# -----------------------------------------------------------------------------
# TERRAFORM SETTINGS
# -----------------------------------------------------------------------------
# This block configures Terraform itself (not AWS).
# - required_version: ensures everyone uses a compatible Terraform version
# - required_providers: locks the AWS provider to a major version to prevent
#   breaking changes from sneaking in on "terraform init"
terraform {
  required_version = ">= 1.5.0" # Minimum Terraform CLI version

  required_providers {
    aws = {
      source  = "hashicorp/aws" # The official AWS provider from HashiCorp
      version = "~> 5.0"        # Any 5.x version (5.0, 5.1, ... but NOT 6.0)
      # The "~>" operator is called the "pessimistic constraint operator".
      # "~> 5.0" means >= 5.0 and < 6.0. This protects you from major version
      # breaking changes while still getting bug fixes and new features.
    }
  }
}

# -----------------------------------------------------------------------------
# AWS PROVIDER CONFIGURATION
# -----------------------------------------------------------------------------
# The provider block tells Terraform HOW to talk to AWS.
# - region: which AWS region to create resources in
#
# AUTHENTICATION:
#   Terraform will look for AWS credentials in this order:
#   1. Environment variables (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
#   2. Shared credentials file (~/.aws/credentials)
#   3. IAM instance profile (if running on an EC2 instance)
#
#   NEVER put credentials directly in .tf files! Use environment variables
#   or the AWS CLI "aws configure" command to set them up.
provider "aws" {
  region = var.aws_region # Default: eu-west-2 (London) — see variables.tf

  # Default tags are automatically applied to EVERY resource created by this
  # provider. This saves you from repeating the same tags everywhere.
  default_tags {
    tags = {
      Project     = var.project_name  # Which project owns these resources
      Environment = var.environment    # dev / staging / production
      ManagedBy   = "terraform"        # So people know not to edit by hand
    }
  }
}

# =============================================================================
# MODULE: VPC (Virtual Private Cloud)
# =============================================================================
# This calls our VPC module to create the network infrastructure.
# Modules are like functions — you pass in variables and get outputs back.
#
# After applying, you can reference outputs like:
#   module.vpc.vpc_id
#   module.vpc.public_subnet_ids
#   module.vpc.private_subnet_ids
module "vpc" {
  source = "./modules/vpc" # Path to the VPC module directory

  # Pass variables to the module. These override the module's defaults.
  # We're using the defaults defined in the module, but being explicit here
  # makes the configuration clearer and self-documenting.
  vpc_cidr             = "10.0.0.0/16"                       # The overall VPC address range
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]     # Public subnet ranges
  private_subnet_cidrs = ["10.0.10.0/24", "10.0.20.0/24"]   # Private subnet ranges
  availability_zones   = ["eu-west-2a", "eu-west-2b"]        # London AZs
  project_name         = var.project_name                     # Passed through from root variables
  environment          = var.environment                      # Passed through from root variables
}

# =============================================================================
# MODULE: ECR (Elastic Container Registry)
# =============================================================================
# This calls our ECR module to create Docker image repositories.
# We need one repository per microservice (frontend + backend).
module "ecr" {
  source = "./modules/ecr" # Path to the ECR module directory

  repository_names = ["multi-tier-frontend", "multi-tier-backend"] # One repo per service
  project_name     = var.project_name
  environment      = var.environment
}

# =============================================================================
# SECURITY GROUPS
# =============================================================================
# Security Groups are virtual firewalls that control inbound and outbound
# traffic for AWS resources. They are STATEFUL, meaning:
#   - If you allow inbound traffic on port 80, the RESPONSE traffic is
#     automatically allowed out (you don't need a separate outbound rule).
#   - If you allow outbound traffic, the RESPONSE traffic is automatically
#     allowed in.
#
# LEAST PRIVILEGE PRINCIPLE:
#   Only open the ports that are absolutely necessary, and only to the sources
#   that need access. This is a core security best practice:
#   - The frontend SG allows traffic from ANYONE (it's public-facing).
#   - The backend SG allows traffic ONLY from the frontend SG.
#   - The database SG allows traffic ONLY from the backend SG.
#   This creates a chain: Internet → Frontend → Backend → Database
#   The database can NEVER be reached directly from the internet.
# =============================================================================

# -----------------------------------------------------------------------------
# FRONTEND SECURITY GROUP
# -----------------------------------------------------------------------------
# This SG is for the frontend service (e.g., a React/Next.js app behind a
# load balancer). It needs to accept HTTP and HTTPS traffic from anywhere
# on the internet because end users will access it via a browser.
resource "aws_security_group" "frontend" {
  name        = "${var.project_name}-frontend-sg"
  description = "Security group for the frontend service — allows HTTP/HTTPS from the internet"
  vpc_id      = module.vpc.vpc_id # Must be in our VPC

  # INBOUND RULE: Allow HTTP (port 80) from anywhere
  # This is how users access your website via http://
  ingress {
    description = "Allow HTTP traffic from anywhere (end users)"
    from_port   = 80      # Start of port range
    to_port     = 80      # End of port range (same = single port)
    protocol    = "tcp"   # HTTP uses TCP
    cidr_blocks = ["0.0.0.0/0"] # 0.0.0.0/0 means "any IPv4 address" — the whole internet
  }

  # INBOUND RULE: Allow HTTPS (port 443) from anywhere
  # This is the encrypted version — https://
  # Always use HTTPS in production. HTTP is fine for learning.
  ingress {
    description = "Allow HTTPS traffic from anywhere (end users)"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # OUTBOUND RULE: Allow ALL traffic out
  # The frontend needs to talk to the backend, download packages, etc.
  # In production you might restrict this further, but for learning,
  # allowing all outbound is fine and common practice.
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0         # 0 means "all ports"
    to_port     = 0         # 0 means "all ports"
    protocol    = "-1"      # "-1" means "all protocols" (TCP, UDP, ICMP, etc.)
    cidr_blocks = ["0.0.0.0/0"] # To anywhere
  }

  tags = {
    Name = "${var.project_name}-frontend-sg"
  }
}

# -----------------------------------------------------------------------------
# BACKEND SECURITY GROUP
# -----------------------------------------------------------------------------
# This SG is for the backend API service (e.g., a Flask/Express app on port 5000).
#
# KEY SECURITY CONCEPT — LEAST PRIVILEGE:
#   Notice we do NOT use cidr_blocks here. Instead, we use
#   "security_groups = [aws_security_group.frontend.id]".
#   This means: "only allow traffic from resources that have the frontend SG
#   attached". This is more secure than IP-based rules because:
#   1. You don't need to know the IP addresses of the frontend instances
#   2. If frontend instances scale up/down, new ones automatically have access
#   3. Nothing else can reach port 5000 — not even you from your laptop
resource "aws_security_group" "backend" {
  name        = "${var.project_name}-backend-sg"
  description = "Security group for the backend API — allows traffic only from the frontend"
  vpc_id      = module.vpc.vpc_id

  # INBOUND RULE: Allow port 5000 from the FRONTEND SECURITY GROUP ONLY
  # Port 5000 is commonly used by Flask (Python) and other API frameworks.
  # The key here is "security_groups" instead of "cidr_blocks" — this
  # restricts access to only resources with the frontend SG attached.
  ingress {
    description     = "Allow API traffic from frontend only (port 5000)"
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend.id] # ONLY from frontend SG!
    # ^ This is SG-to-SG referencing — a powerful AWS networking pattern.
    # It means "trust any resource that has the frontend security group".
  }

  # OUTBOUND RULE: Allow ALL traffic out
  # The backend needs to reach the database, external APIs, package managers, etc.
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-backend-sg"
  }
}

# -----------------------------------------------------------------------------
# DATABASE SECURITY GROUP
# -----------------------------------------------------------------------------
# This SG is for the PostgreSQL database (RDS or a container running Postgres).
#
# DEFENCE IN DEPTH:
#   This is the innermost layer of our security model:
#     Internet → (blocked) → Frontend SG → (port 5000) → Backend SG → (port 5432) → Database SG
#   An attacker would need to compromise BOTH the frontend AND the backend
#   before they could even attempt to reach the database. This is called
#   "defence in depth" — multiple layers of security.
#
#   Port 5432 is the default PostgreSQL port. If you use MySQL, change to 3306.
resource "aws_security_group" "database" {
  name        = "${var.project_name}-database-sg"
  description = "Security group for the database — allows traffic only from the backend"
  vpc_id      = module.vpc.vpc_id

  # INBOUND RULE: Allow PostgreSQL (port 5432) from the BACKEND SECURITY GROUP ONLY
  # Only the backend can talk to the database. The frontend cannot.
  # The internet definitely cannot. This is least privilege in action.
  ingress {
    description     = "Allow PostgreSQL traffic from backend only (port 5432)"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.backend.id] # ONLY from backend SG!
    # ^ Same pattern as above: SG-to-SG reference. Only resources with the
    #   backend security group can connect to the database.
  }

  # OUTBOUND RULE: Allow ALL traffic out
  # The database might need outbound access for things like:
  # - Sending logs to CloudWatch
  # - Downloading updates (for self-managed databases)
  # For RDS (managed databases), AWS handles most of this, but allowing
  # all outbound is standard practice.
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-database-sg"
  }
}
