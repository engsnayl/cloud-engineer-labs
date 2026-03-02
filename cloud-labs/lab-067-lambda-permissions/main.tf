# Lambda Permissions Lab
provider "aws" {
  region = "eu-west-2"
}

resource "aws_s3_bucket" "uploads" {
  bucket = "uploads-${random_id.suffix.hex}"
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda-processor-role"

  # BUG 1: Trust policy doesn't allow Lambda service
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda-policy"
  role = aws_iam_role.lambda_role.id

  # BUG 2: Missing CloudWatch Logs permissions
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "${aws_s3_bucket.uploads.arn}/*"
    }]
  })
}

resource "aws_lambda_function" "processor" {
  filename         = "lambda.zip"
  function_name    = "upload-processor"
  role             = aws_iam_role.lambda_role.arn
  handler          = "index.handler"
  runtime          = "python3.11"
  source_code_hash = filebase64sha256("lambda.zip")
}

# BUG 3: Missing S3 bucket notification and Lambda permission
# The S3 bucket can't invoke the Lambda without these

resource "random_id" "suffix" {
  byte_length = 4
}
