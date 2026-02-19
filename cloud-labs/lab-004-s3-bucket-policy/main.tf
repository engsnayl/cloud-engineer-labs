# S3 Bucket Policy Lab
provider "aws" {
  region = "eu-west-2"
}

resource "aws_s3_bucket" "app_data" {
  bucket = "app-data-${random_id.suffix.hex}"
}

resource "aws_s3_bucket_policy" "app_data" {
  bucket = aws_s3_bucket.app_data.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # BUG 1: Effect is Deny instead of Allow
        Effect    = "Deny"
        Principal = "*"
        Action    = ["s3:GetObject", "s3:PutObject"]
        Resource  = "${aws_s3_bucket.app_data.arn}/*"
      },
      {
        Effect    = "Allow"
        Principal = {
          AWS = aws_iam_role.app_role.arn
        }
        Action    = ["s3:ListBucket"]
        # BUG 2: Wrong resource — ListBucket needs bucket ARN, not object ARN
        Resource  = "${aws_s3_bucket.app_data.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role" "app_role" {
  name = "app-s3-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "app_s3" {
  name = "app-s3-policy"
  role = aws_iam_role.app_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
      # BUG 3: Resource should include both bucket and objects
      Resource = aws_s3_bucket.app_data.arn
    }]
  })
}

resource "random_id" "suffix" {
  byte_length = 4
}
