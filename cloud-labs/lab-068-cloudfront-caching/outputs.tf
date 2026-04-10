# =============================================================================
# Lab 068 — Outputs
# =============================================================================
# Exposed values for use by the validator, diagnostic commands, and the
# learner's curl/invalidation steps during the walkthrough.
# =============================================================================

output "distribution_id" {
  description = "CloudFront distribution ID — used for get-distribution and create-invalidation"
  value       = aws_cloudfront_distribution.website.id
}

output "distribution_domain_name" {
  description = "CloudFront distribution domain name — the URL to curl when reproducing the fault"
  value       = aws_cloudfront_distribution.website.domain_name
}

output "bucket_name" {
  description = "S3 bucket name — used for uploading test content via aws s3 cp"
  value       = aws_s3_bucket.website.id
}
