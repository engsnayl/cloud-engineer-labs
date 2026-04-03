Title: Terraform State Mismatch — Drift Detection
Difficulty: ⭐⭐⭐ Advanced | Estimated Time: 25–30 mins | Category: Terraform / State

## Scenario

> **INCIDENT-TF-002:** Terraform plan shows it wants to destroy and recreate resources that should stay. Someone made manual changes via the AWS console. State is out of sync with reality.

Infrastructure was previously applied. Since then, changes were made directly in the AWS console without going through Terraform. The config hasn't been updated. Your job is to reconcile everything.

## Objectives

1. Read and interpret `terraform plan` output — identify each type of drift
2. Fix the S3 bucket tags in `main.tf` to match the intended production values
3. Fix the versioning configuration in `main.tf` to reflect the console change
4. Understand how Terraform handles a resource deleted outside of Terraform
5. `terraform validate` must pass
6. `terraform plan` must complete without errors

## Validation

Lab Validate 061

See SOLUTION.md for full setup instructions and walkthrough.
