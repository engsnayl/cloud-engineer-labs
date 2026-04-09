# Remote Backend Lab


provider "aws" {
  region = "eu-west-2"
}

# TASK: Add a terraform backend block for S3
# terraform {
#   backend "s3" {
#     bucket         = "terraform-state-340752829546"
#     key            = "production/terraform.tfstate"
#     region         = "eu-west-2"
#     dynamodb_table = "terraform-locks"
#     encrypt        = true
#   }
# }

resource "aws_s3_bucket" "terraform_state" {
  bucket = "terraform-state-340752829546"
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Missing DynamoDB table for state locking
# resource "aws_dynamodb_table" "terraform_locks" {
#   name         = "terraform-locks"
#   billing_mode = "PAY_PER_REQUEST"
#   hash_key     = "LockID"
#   attribute {
#     name = "LockID"
#     type = "S"
#   }
# }

# Missing server-side encryption on state bucket
# resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
#   ...
# }

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "production-vpc" }
}
