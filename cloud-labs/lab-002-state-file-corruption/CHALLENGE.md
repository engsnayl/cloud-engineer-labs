Title: Terraform State Mismatch — Drift Detection
Difficulty: ⭐⭐⭐ (Advanced)
Time: 20-25 minutes
Category: Terraform / State
Skills: terraform state, terraform import, terraform refresh, state manipulation

## Scenario

Someone manually modified AWS resources through the console, causing Terraform state to drift from reality. Terraform plan shows unexpected changes.

> **INCIDENT-TF-002**: Terraform plan shows it wants to destroy and recreate resources that should stay. Someone made manual changes via the console. State is out of sync with reality.

## How to Use This Lab

1. Review the Terraform files — find and fix the bugs
2. Run `terraform init && terraform plan` to see errors
3. Fix the issues in main.tf
4. Run `terraform plan` to verify no errors remain
5. (Optional) `terraform apply` if using a real AWS account or KodeKloud Playground

**Requires:** Terraform installed. AWS credentials for apply (optional — you can learn from plan alone).

## Validation

Run `./validate.sh` or manually verify with `terraform plan` showing no unexpected changes.
