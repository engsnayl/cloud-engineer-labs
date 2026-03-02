Title: S3 Access Denied — Bucket Policy Debugging
Difficulty: ⭐⭐ (Intermediate)
Time: 15-20 minutes
Category: AWS / S3
Skills: S3 bucket policies, IAM policies, policy simulator, CloudTrail

## Scenario

The application can't read from or write to its S3 bucket. The bucket policy and IAM role are both configured but something is blocking access.

> **INCIDENT-AWS-001**: Application returning "Access Denied" on all S3 operations. Bucket policy exists. IAM role is attached. CloudTrail shows explicit deny but we can't find where.

## Objectives

1. Fix the S3 bucket policy so the application role can access objects
2. Resolve any explicit deny rules blocking access
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
