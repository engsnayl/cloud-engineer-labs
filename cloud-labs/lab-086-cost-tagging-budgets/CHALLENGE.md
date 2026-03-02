Title: No Cost Visibility — Tagging Strategy & Budget Alarms
Difficulty: ⭐⭐ (Intermediate)
Time: 15-20 minutes
Category: AWS / Cost Management
Skills: AWS resource tagging, Budgets, CloudWatch billing alarms, cost allocation tags, Terraform

## Scenario

Finance is asking why the AWS bill jumped 40% last month. Nobody can tell which team or project caused the increase because resources aren't properly tagged, there are no budget alarms, and cost allocation is impossible.

> **INCIDENT-COST-001**: Monthly AWS bill increased from £8,000 to £11,200 with no visibility into which project or team caused the increase. CFO wants cost controls and alerting in place by Friday.

## Objectives

1. Fix the tagging strategy so all resources have consistent Environment, Project, Team, and CostCentre tags
2. Fix the AWS Budget configuration so it alerts at 80% and 100% thresholds
3. Fix the CloudWatch billing alarm for the monthly budget ceiling
4. Fix the SNS topic that delivers budget alerts
5. `terraform validate` must pass
6. `terraform plan` must complete without errors

**Requires:** Terraform installed. AWS credentials for apply (optional).

## Validation

Run `./validate.sh` or manually verify with `terraform plan`.
