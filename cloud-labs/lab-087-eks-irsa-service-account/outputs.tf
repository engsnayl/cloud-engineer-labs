output "cluster_name" {
  value       = aws_eks_cluster.main.name
  description = "EKS cluster name"
}

output "cluster_endpoint" {
  value       = aws_eks_cluster.main.endpoint
  description = "EKS API endpoint"
}

output "oidc_issuer" {
  value       = aws_eks_cluster.main.identity[0].oidc[0].issuer
  description = "OIDC issuer URL for IRSA"
}

output "app_role_arn" {
  value       = aws_iam_role.app_role.arn
  description = "ARN of the IAM role the pod should assume"
}

output "s3_bucket_name" {
  value       = aws_s3_bucket.app_data.bucket
  description = "S3 bucket the pod should access"
}

output "dynamodb_table_name" {
  value       = aws_dynamodb_table.app_state.name
  description = "DynamoDB table the pod should access"
}

output "region" {
  value       = var.region
  description = "AWS region"
}
