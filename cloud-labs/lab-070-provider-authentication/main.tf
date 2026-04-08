provider "aws" {
  region = "eu-west-99"
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "backup" {
  provider = aws.backup_region
  bucket   = "backup-data-bucket"
}

resource "aws_s3_bucket" "primary" {
  bucket = "primary-data-bucket"
}
