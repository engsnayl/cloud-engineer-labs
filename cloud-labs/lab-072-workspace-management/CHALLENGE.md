Title: Wrong Environment — Terraform Workspace Confusion
Difficulty: ⭐⭐ (Intermediate)
Time: 15-20 minutes
Category: Terraform / Workspaces
Skills: terraform workspace, environment separation, workspace-aware configuration, state isolation

## Scenario

You've been handed an incident ticket from the on-call engineer:

> **INCIDENT-TF-006**: Production is behaving like staging. Instances are undersized and all environment tags in AWS are showing the wrong environment name — including on resources we know are in production. We manage both environments with Terraform. Please investigate the Terraform configuration and fix it so each environment deploys with the correct settings.
>
> Production should be: instance type t3.large, ASG min 2 / max 10 / desired 2, Environment tag "production"
>
> Staging should be: instance type t3.micro, ASG min 1 / max 2 / desired 1, Environment tag "staging"

## Objectives

1. Identify why the Terraform configuration is producing the same output regardless of environment
2. Fix the configuration so each workspace deploys the correct instance type, scaling settings, and environment tag
3. `terraform validate` must pass
4. `terraform plan` must complete without errors and show correct values per workspace

## How to Use This Lab

1. Review the Terraform files — understand what's here before touching anything
2. Run `terraform workspace list` to see what workspaces exist
3. Read main.tf carefully — look for anything that should differ between environments but doesn't
4. Fix the issues in main.tf
5. Run `terraform plan` in each workspace to verify the correct values appear
6. (Optional) `terraform apply` if using a real AWS account or KodeKloud Playground

**Requires:** Terraform installed. AWS credentials for apply (optional — you can learn from plan alone).
