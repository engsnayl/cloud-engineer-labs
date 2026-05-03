# =============================================================================
# FILE: modules/ecr/main.tf
# PURPOSE: Creates ECR (Elastic Container Registry) repositories to store
#          our Docker images for the frontend and backend services.
#
# WHAT IS ECR?
#   ECR is AWS's private Docker image registry — like Docker Hub, but private
#   to your AWS account. When we build Docker images for our app, we push them
#   to ECR. Then, when ECS/EKS needs to run a container, it pulls the image
#   from ECR.
#
# WHY NOT JUST USE DOCKER HUB?
#   - ECR is private by default (Docker Hub free tier is public)
#   - ECR integrates natively with ECS/EKS (no extra authentication setup)
#   - ECR image scanning finds security vulnerabilities automatically
#   - Data stays within your AWS account and region (lower latency, compliance)
#
# COST NOTE:
#   ECR charges for storage (~$0.10/GB/month). The lifecycle policy below
#   automatically deletes old images to keep costs low.
# =============================================================================

# -----------------------------------------------------------------------------
# ECR REPOSITORIES
# -----------------------------------------------------------------------------
# We create one repository per service (frontend, backend).
# "for_each" creates one resource per item in the set. Unlike "count" which
# uses numeric indexes (0, 1, 2...), for_each uses the actual values as keys.
# This is better because adding/removing items won't cause other repos to
# be destroyed and recreated.
resource "aws_ecr_repository" "repos" {
  for_each = toset(var.repository_names) # Convert list to set for for_each

  name = each.value # The repository name, e.g., "multi-tier-frontend"

  # IMAGE TAG MUTABILITY
  # "MUTABLE" means you can push a new image with the same tag (e.g., :latest)
  # and it will overwrite the old one. This is convenient for learning/development.
  # In production, you'd use "IMMUTABLE" to prevent accidental overwrites and
  # ensure each deployment uses a unique, traceable image tag.
  image_tag_mutability = "MUTABLE"

  # IMAGE SCANNING
  # When enabled, ECR automatically scans every pushed image for known security
  # vulnerabilities (CVEs). This is a free feature — always enable it!
  # You can view scan results in the AWS Console under each image.
  image_scanning_configuration {
    scan_on_push = true # Scan every image as soon as it's pushed
  }

  tags = {
    Name        = "${var.project_name}-${each.value}" # e.g., "multi-tier-app-multi-tier-frontend"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}

# -----------------------------------------------------------------------------
# LIFECYCLE POLICY — KEEP ONLY THE LAST 5 IMAGES
# -----------------------------------------------------------------------------
# Docker images can be large (100MB–1GB+). Without cleanup, your ECR storage
# costs will grow forever. This policy automatically deletes old images,
# keeping only the most recent 5 per repository.
#
# HOW IT WORKS:
#   - "rulePriority": 1 — rules are evaluated in priority order (1 = first)
#   - "tagStatus": "any" — applies to all images regardless of tags
#   - "countType": "imageCountMoreThan" — trigger when more than N images exist
#   - "countNumber": 5 — keep 5, delete the rest (oldest first)
#
# You can view and edit these policies in the AWS Console too, but defining
# them in Terraform ensures they're consistent and version-controlled.
resource "aws_ecr_lifecycle_policy" "cleanup" {
  for_each = toset(var.repository_names) # One policy per repository

  repository = aws_ecr_repository.repos[each.value].name # Which repo this policy applies to

  # The policy is defined as a JSON string. Terraform's "jsonencode" function
  # converts a Terraform map/list into valid JSON — easier than writing raw JSON.
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1                    # This is the first (and only) rule
        description  = "Keep only the last 5 images to control storage costs"
        selection = {
          tagStatus   = "any"               # Apply to ALL images (tagged and untagged)
          countType   = "imageCountMoreThan" # Trigger based on image count
          countNumber = 5                    # Keep this many images
        }
        action = {
          type = "expire"                   # Delete images that exceed the count
        }
      }
    ]
  })
}
