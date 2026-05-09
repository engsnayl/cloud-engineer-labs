variable "project_name" {
  description = "Project identifier used in resource names and tags"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
}

variable "repository_names" {
  description = "List of ECR repository names to create (one per image)"
  type        = list(string)
}

variable "image_tag_mutability" {
  description = "MUTABLE allows :latest to be overwritten; IMMUTABLE locks tags. Use IMMUTABLE in production."
  type        = string
  default     = "MUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be MUTABLE or IMMUTABLE."
  }
}

variable "scan_on_push" {
  description = "Run vulnerability scan on every image push"
  type        = bool
  default     = true
}

variable "max_tagged_images" {
  description = "How many tagged images to keep before lifecycle policy expires the oldest"
  type        = number
  default     = 10
}

variable "untagged_expire_days" {
  description = "Days to keep untagged images before lifecycle policy expires them"
  type        = number
  default     = 7
}
