Title: Terraform Can't Authenticate — Provider Configuration
Difficulty: ⭐⭐ (Intermediate)
Time: 10-15 minutes
Category: Terraform / Providers
Skills: terraform providers, AWS credential chain, provider aliases, region config

## Scenario

Terraform init and plan are failing with authentication errors. The provider configuration has issues with region settings and credential references.

> **INCIDENT-TF-004**: Terraform plan failing with "no valid credential sources". Provider block appears to be configured but something is wrong with the authentication chain.

## Objectives

1. Fix the Terraform provider configuration (region, credentials, aliases)
2. Ensure the authentication chain is correctly configured
3. `terraform validate` must pass
4. `terraform plan` must complete without errors

## How to Use This Lab

1. Review the Terraform files — find and fix the bugs
2. Run `terraform init && terraform plan` to see errors
3. Fix the issues in main.tf
4. Run `terraform plan` to verify no errors remain
5. (Optional) `terraform apply` if using a real AWS account or KodeKloud Playground

**Requires:** Terraform installed. AWS credentials for apply (optional — you can learn from plan alone).
