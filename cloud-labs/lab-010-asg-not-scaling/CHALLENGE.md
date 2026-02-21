Title: ASG Not Scaling — Auto Scaling Group Issues
Difficulty: ⭐⭐⭐ (Advanced)
Time: 20-25 minutes
Category: AWS / Auto Scaling
Skills: ASG, launch templates, scaling policies, CloudWatch alarms, health checks

## Scenario

The Auto Scaling Group should scale up when CPU exceeds 70% but it's not responding. Instances are at high CPU but the ASG stays at minimum capacity.

> **INCIDENT-AWS-007**: ASG not scaling despite high CPU. CloudWatch alarm showing ALARM state. ASG desired count stays at 1. Launch template and scaling policy appear configured.

## Objectives

1. Fix the Auto Scaling Group configuration so scaling policies trigger correctly
2. Ensure the scaling policy is linked to the correct CloudWatch alarm
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
