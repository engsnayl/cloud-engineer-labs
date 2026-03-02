Title: State File Lost — Remote Backend Configuration
Difficulty: ⭐⭐⭐ (Advanced)
Time: 20-25 minutes
Category: Terraform / State
Skills: remote backend, S3 state, DynamoDB locking, state migration, backend config

## Scenario

The team has been running Terraform with local state files and just lost a colleague's laptop with the only copy of the production state. Time to set up a remote backend.

> **INCIDENT-TF-007**: Production Terraform state lost. Local state file was on a laptop that died. Need to configure S3 remote backend with DynamoDB locking to prevent this happening again.

## Objectives

1. Configure the S3 remote backend for state storage
2. Set up DynamoDB table for state locking
3. `terraform validate` must pass
4. `terraform plan` must complete without errors

## How to Use This Lab

1. Review the Terraform files — find and fix the bugs
2. Run `terraform init && terraform plan` to see errors
3. Fix the issues in main.tf
4. Run `terraform plan` to verify no errors remain
5. (Optional) `terraform apply` if using a real AWS account or KodeKloud Playground

**Requires:** Terraform installed. AWS credentials for apply (optional — you can learn from plan alone).
