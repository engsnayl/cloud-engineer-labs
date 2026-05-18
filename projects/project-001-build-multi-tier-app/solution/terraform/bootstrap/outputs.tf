output "state_bucket_name" {
  description = "S3 bucket name for Terraform remote state. Reference this in the main workspace's backend block."
  value       = aws_s3_bucket.tfstate.id
}

output "state_bucket_arn" {
  description = "ARN of the state bucket."
  value       = aws_s3_bucket.tfstate.arn
}

output "lock_table_name" {
  description = "DynamoDB table name for Terraform state locking. Reference this in the main workspace's backend block."
  value       = aws_dynamodb_table.tf_locks.id
}

output "region" {
  description = "AWS region the backend lives in."
  value       = "eu-west-1"
}
