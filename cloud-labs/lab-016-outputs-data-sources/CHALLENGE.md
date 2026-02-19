Title: Can't Reference Resources — Outputs and Data Sources
Difficulty: ⭐⭐ (Intermediate)
Time: 15-20 minutes
Category: Terraform / Data
Skills: outputs, data sources, terraform_remote_state, data lookups, AMI lookup

## Scenario

The Terraform configuration can't find the AMI it needs and the outputs aren't exposing the right information for other modules to consume.

> **INCIDENT-TF-009**: Terraform apply failing because AMI ID is hardcoded and doesn't exist in this region. Outputs are missing critical information that downstream modules need.

## How to Use This Lab

1. Review the Terraform files — find and fix the bugs
2. Run `terraform init && terraform plan` to see errors
3. Fix the issues in main.tf
4. Run `terraform plan` to verify no errors remain
5. (Optional) `terraform apply` if using a real AWS account or KodeKloud Playground

**Requires:** Terraform installed. AWS credentials for apply (optional — you can learn from plan alone).
