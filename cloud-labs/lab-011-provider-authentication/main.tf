# Provider Authentication Lab
# BUG 1: Region is invalid
provider "aws" {
  region = "eu-west-99"
}

# BUG 2: Second provider missing alias
provider "aws" {
  region = "us-east-1"
}

# BUG 3: Resource references non-existent provider alias
resource "aws_s3_bucket" "backup" {
  provider = aws.backup_region
  bucket   = "backup-data-bucket"
}

resource "aws_s3_bucket" "primary" {
  bucket = "primary-data-bucket"
}
