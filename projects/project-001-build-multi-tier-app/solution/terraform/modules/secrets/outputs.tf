output "secret_arn" {
  description = "ARN of the AWS Secrets Manager secret. Referenced by the ExternalSecret manifest's secretKey field is NOT this — this is for IAM policy scoping and operator config."
  value       = aws_secretsmanager_secret.db.arn
}

output "secret_name" {
  description = "Name of the AWS Secrets Manager secret. Referenced by the ExternalSecret manifest's data.remoteRef.key field."
  value       = aws_secretsmanager_secret.db.name
}

output "iam_user_name" {
  description = "Name of the IAM user ESO authenticates as. Useful for audit and console lookup."
  value       = aws_iam_user.eso.name
}

output "iam_user_arn" {
  description = "ARN of the IAM user ESO authenticates as."
  value       = aws_iam_user.eso.arn
}

output "access_key_id" {
  description = "Access key ID for the ESO IAM user. Bootstrap into the cluster as part of the aws-creds Secret."
  value       = aws_iam_access_key.eso.id
}

output "access_key_secret" {
  description = "Secret access key for the ESO IAM user. SENSITIVE — bootstrap into the cluster as part of the aws-creds Secret. Marked sensitive to suppress CLI display, but still stored in plain text in the Terraform state file."
  value       = aws_iam_access_key.eso.secret
  sensitive   = true
}
