Title: Module Won't Apply — Dependency Issues
Difficulty: ⭐⭐ (Intermediate)
Time: 15-20 minutes
Category: Terraform / Modules
Skills: terraform modules, depends_on, outputs, module references

## Scenario

A modular Terraform configuration won't apply because of circular dependencies and incorrect module references.

> **INCIDENT-TF-003**: Terraform apply failing with dependency errors. VPC module outputs aren't being passed correctly to the EC2 module. New engineer refactored into modules but broke the references.

## Objectives

1. Fix the module dependency chain — outputs from one module must be correctly passed to dependent modules
2. Resolve any circular or missing dependencies
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
