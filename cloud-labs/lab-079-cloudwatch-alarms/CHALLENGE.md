Title: No Alerts Firing — CloudWatch Alarms Misconfigured
Difficulty: ⭐⭐ (Intermediate)
Time: 15-20 minutes
Category: AWS / CloudWatch
Skills: CloudWatch alarms, metrics, dimensions, SNS topics, alarm actions

## Scenario

CloudWatch alarms should be alerting the team when resources are unhealthy, but no alarms are firing despite known issues.

> **INCIDENT-AWS-011**: No CloudWatch alarms triggered during last outage. Alarms exist but appear misconfigured. Team didn't get notified until customers complained.

## Objectives

1. Fix the CloudWatch alarm configuration (metrics, thresholds, and actions)
2. Ensure alarms are connected to the correct SNS topic for notifications
3. `terraform validate` must pass
4. `terraform plan` must complete without errors

## How to Use This Lab

1. Review the Terraform files — find and fix the bugs
2. Run `terraform init && terraform plan` to see errors
3. Fix the issues in main.tf
4. Run `terraform plan` to verify no errors remain
5. (Optional) `terraform apply` if using a real AWS account or KodeKloud Playground

**Requires:** Terraform installed. AWS credentials for apply (optional — you can learn from plan alone).
