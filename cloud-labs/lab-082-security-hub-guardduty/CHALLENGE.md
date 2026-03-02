Title: Security Findings Ignored — Security Hub & GuardDuty Misconfigured
Difficulty: ⭐⭐⭐ (Advanced)
Time: 20-25 minutes
Category: AWS / Security
Skills: Security Hub, GuardDuty, IAM, EventBridge, SNS, Terraform

## Scenario

Your company just passed an external audit — barely. The auditors flagged that AWS Security Hub and GuardDuty are deployed but not working effectively. Findings aren't being aggregated, GuardDuty isn't monitoring all required regions, and the alerting pipeline for critical findings is broken.

> **INCIDENT-SEC-001**: Security team reports they haven't received any GuardDuty alerts in 3 weeks despite known suspicious activity in dev accounts. Security Hub console shows "No findings" even though GuardDuty is supposedly enabled.

## Objectives

1. Fix GuardDuty configuration so it's actively detecting threats
2. Fix Security Hub so it aggregates findings from GuardDuty
3. Fix the EventBridge rule that routes critical findings to SNS
4. Fix the SNS topic policy so Security Hub can publish to it
5. `terraform validate` must pass
6. `terraform plan` must complete without errors

## How to Use This Lab

1. Review the Terraform files — find and fix the bugs
2. Run `terraform init && terraform plan` to see errors
3. Fix the issues in main.tf
4. Run `terraform plan` to verify no errors remain
5. (Optional) `terraform apply` if using a real AWS account or KodeKloud Playground

**Requires:** Terraform installed. AWS credentials for apply (optional — you can learn from plan alone).

## Validation

Run `./validate.sh` or manually verify with `terraform plan` showing no unexpected changes.
