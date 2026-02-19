# Terraform State Drift Lab
# Some resources were modified outside of Terraform

provider "aws" {
  region = "eu-west-2"
}

resource "aws_s3_bucket" "data" {
  bucket = "company-data-${random_id.suffix.hex}"
  # BUG 1: Tags were modified in console — Terraform wants to revert them
  tags = {
    Environment = "production"
    Team        = "engineering"
  }
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id
  versioning_configuration {
    # BUG 2: Versioning was enabled in console but Terraform says Disabled
    status = "Disabled"
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}

# BUG 3: This security group was deleted manually in console
# Terraform still thinks it exists in state
resource "aws_security_group" "app" {
  name        = "app-sg"
  description = "Application security group"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
