Title: Wrong Environment — Terraform Workspace Confusion
Difficulty: ⭐⭐ (Intermediate)
Time: 15-20 minutes
Category: Terraform / Workspaces
Skills: terraform workspace, environment separation, variable per workspace, state isolation

## Scenario

The team accidentally applied staging configuration to production because they were in the wrong Terraform workspace. The configuration uses workspaces but isn't properly parameterised.

> **INCIDENT-TF-006**: Staging instance types and scaling applied to production. Terraform workspaces in use but configuration doesn't vary by workspace. Need to fix workspace-aware config.

## Objectives

1. Fix the workspace configuration so each environment gets the correct settings
2. Ensure `terraform.workspace` is used to differentiate environments
3. `terraform validate` must pass
4. `terraform plan` must complete without errors

## How to Use This Lab

1. Review the Terraform files — find and fix the bugs
2. Run `terraform init && terraform plan` to see errors
3. Fix the issues in main.tf
4. Run `terraform plan` to verify no errors remain
5. (Optional) `terraform apply` if using a real AWS account or KodeKloud Playground

**Requires:** Terraform installed. AWS credentials for apply (optional — you can learn from plan alone).
