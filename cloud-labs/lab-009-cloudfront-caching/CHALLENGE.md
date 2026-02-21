Title: CloudFront Serving Stale Content — Cache Issues
Difficulty: ⭐⭐⭐ (Advanced)
Time: 20-25 minutes
Category: AWS / CloudFront
Skills: CloudFront, cache behaviours, origin configuration, TTL, invalidation

## Scenario

CloudFront is serving outdated content. The S3 origin has been updated but CloudFront keeps returning the old version. The cache configuration needs fixing.

> **INCIDENT-AWS-006**: Website showing old content despite S3 updates. CloudFront distribution not reflecting origin changes. Customer complaints about outdated pricing page.

## Objectives

1. Fix the CloudFront distribution origin and cache behaviour configuration
2. Ensure the origin correctly points to the S3 bucket
3. `terraform validate` must pass
4. `terraform plan` must complete without errors

## How to Use This Lab

1. Review the Terraform files — find and fix the bugs
2. Run `terraform init && terraform plan` to see errors
3. Fix the issues in main.tf
4. Run `terraform plan` to verify no errors remain
5. (Optional) `terraform apply` if using a real AWS account or KodeKloud Playground

**Requires:** Terraform installed. AWS credentials for apply (optional — you can learn from plan alone).

## Validation

Run `./validate.sh` or manually verify with `terraform plan` showing no unexpected changes.
