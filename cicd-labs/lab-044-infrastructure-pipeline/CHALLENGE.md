Title: IaC Pipeline — Terraform in CI/CD
Difficulty: ⭐⭐⭐ (Advanced)
Time: 20-25 minutes
Category: CI/CD / Infrastructure
Skills: Terraform in CI, plan/apply workflow, approval gates, state locking

## Scenario

The infrastructure-as-code pipeline needs to safely run Terraform plan on PRs and apply on merge, with proper approval gates and state management.

> **INCIDENT-CICD-005**: Junior engineer ran terraform apply locally and broke production. Need a CI pipeline that enforces plan review before apply. No more local applies.

## How to Use This Lab

1. Read the CHALLENGE.md for context
2. Examine the pipeline/workflow files
3. Find and fix the bugs
4. Run validate.sh to check your fixes

**Requires:** Understanding of CI/CD concepts. Some labs can be tested with `act` (local GitHub Actions runner) or Docker.
