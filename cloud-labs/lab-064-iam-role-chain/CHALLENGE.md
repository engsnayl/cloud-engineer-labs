Title: IAM Role Assumption Failed — Trust Policy Broken
Difficulty: ⭐⭐⭐ (Advanced)
Time: 20-25 minutes
Category: AWS / IAM
Skills: IAM roles, trust policies, assume role, cross-account, STS

## Scenario

The application needs to assume a cross-account role to access resources in a shared services account, but the AssumeRole call is failing.

> **INCIDENT-AWS-002**: Application can't assume cross-account role. STS AssumeRole returning "Access Denied". Both the trust policy and the IAM policy seem to be configured. Something in the chain is broken.

## Objectives

1. Fix the IAM trust policy for cross-account role assumption
2. Ensure the role chain allows STS AssumeRole to succeed
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
