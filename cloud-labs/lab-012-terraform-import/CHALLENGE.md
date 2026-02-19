Title: Existing Resources — Terraform Import and Adoption
Difficulty: ⭐⭐⭐ (Advanced)
Time: 20-25 minutes
Category: Terraform / State
Skills: terraform import, terraform state, resource adoption, data sources

## Scenario

Resources were created manually in the AWS console and now need to be brought under Terraform management. The Terraform config exists but the state doesn't know about the existing resources.

> **INCIDENT-TF-005**: Team wants to manage manually-created resources with Terraform. Running terraform apply would create duplicates. Need to import existing resources into state.

## How to Use This Lab

1. Review the Terraform files — find and fix the bugs
2. Run `terraform init && terraform plan` to see errors
3. Fix the issues in main.tf
4. Run `terraform plan` to verify no errors remain
5. (Optional) `terraform apply` if using a real AWS account or KodeKloud Playground

**Requires:** Terraform installed. AWS credentials for apply (optional — you can learn from plan alone).
