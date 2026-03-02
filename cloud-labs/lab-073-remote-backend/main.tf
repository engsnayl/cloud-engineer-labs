# Remote Backend Lab
# BUG: No backend configured — state is local only

provider "aws" {
  region = "eu-west-2"
}

# TASK: Add a terraform backend block for S3
# terraform {
#   backend "s3" {
#     bucket         = "terraform-state-ACCOUNT_ID"
#     key            = "production/terraform.tfstate"
#     region         = "eu-west-2"
#     dynamodb_table = "terraform-locks"
#     encrypt        = true
#   }
# }

# Create the backend infrastructure itself
resource "aws_s3_bucket" "terraform_state" {
  bucket = "terraform-state-lab"
  
  # BUG 1: Missing versioning (critical for state files)
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# BUG 2: Missing DynamoDB table for state locking
# resource "aws_dynamodb_table" "terraform_locks" {
#   name         = "terraform-locks"
#   billing_mode = "PAY_PER_REQUEST"
#   hash_key     = "LockID"
#   attribute {
#     name = "LockID"
#     type = "S"
#   }
# }

# BUG 3: Missing server-side encryption on state bucket
# resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
#   ...
# }

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "production-vpc" }
}
