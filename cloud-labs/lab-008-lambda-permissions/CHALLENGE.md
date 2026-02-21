Title: Lambda Can't Execute — Missing Permissions
Difficulty: ⭐⭐ (Intermediate)
Time: 15-20 minutes
Category: AWS / Lambda
Skills: Lambda, IAM execution role, CloudWatch Logs, S3 triggers

## Scenario

A Lambda function triggered by S3 uploads isn't working. It has permission issues preventing it from executing and writing logs.

> **INCIDENT-AWS-005**: S3-triggered Lambda not processing uploads. Function exists but CloudWatch shows no invocation logs. Suspect IAM and trigger configuration issues.

## Objectives

1. Fix the Lambda execution role so it has CloudWatch Logs permissions
2. Configure the S3 event trigger and Lambda invoke permissions correctly
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
