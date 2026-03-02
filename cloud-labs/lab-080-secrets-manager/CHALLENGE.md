Title: Secrets Not Rotating — Secrets Manager Configuration
Difficulty: ⭐⭐⭐ (Advanced)
Time: 20-25 minutes
Category: AWS / Secrets Manager
Skills: Secrets Manager, rotation, Lambda rotation function, IAM permissions

## Scenario

The database password hasn't rotated in 90 days despite a rotation policy being configured. The rotation Lambda function isn't executing.

> **INCIDENT-AWS-012**: Security audit flagged database password hasn't rotated. Secrets Manager rotation is configured but Lambda rotation function failing. Credentials may be compromised.

## Objectives

1. Fix the Secrets Manager secret rotation configuration
2. Ensure the rotation Lambda function has correct permissions
3. `terraform validate` must pass
4. `terraform plan` must complete without errors

## How to Use This Lab

1. Review the Terraform files — find and fix the bugs
2. Run `terraform init && terraform plan` to see errors
3. Fix the issues in main.tf
4. Run `terraform plan` to verify no errors remain
5. (Optional) `terraform apply` if using a real AWS account or KodeKloud Playground

**Requires:** Terraform installed. AWS credentials for apply (optional — you can learn from plan alone).
