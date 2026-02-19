Title: Terraform Logic Errors — Conditionals and Loops
Difficulty: ⭐⭐ (Intermediate)
Time: 15-20 minutes
Category: Terraform / HCL
Skills: count, for_each, conditionals, ternary operator, dynamic blocks, locals

## Scenario

The Terraform configuration uses conditionals and loops to manage resources across environments, but the logic has bugs causing wrong resources to be created.

> **INCIDENT-TF-008**: Production deployment creating resources that should only exist in staging, and missing resources that should exist in production. Conditional logic in Terraform is wrong.

## How to Use This Lab

1. Review the Terraform files — find and fix the bugs
2. Run `terraform init && terraform plan` to see errors
3. Fix the issues in main.tf
4. Run `terraform plan` to verify no errors remain
5. (Optional) `terraform apply` if using a real AWS account or KodeKloud Playground

**Requires:** Terraform installed. AWS credentials for apply (optional — you can learn from plan alone).
