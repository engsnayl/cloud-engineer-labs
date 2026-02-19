Title: ECS Service Won't Start — Task Definition Errors
Difficulty: ⭐⭐⭐ (Advanced)
Time: 20-25 minutes
Category: AWS / ECS
Skills: ECS, task definitions, container definitions, IAM roles, service configuration

## Scenario

The ECS service keeps failing to start tasks. The task definition has several configuration issues preventing containers from launching.

> **INCIDENT-AWS-009**: ECS service "payment-api" stuck at 0 running tasks. Task attempts failing with multiple errors. Task definition was recently updated.

## How to Use This Lab

1. Review the Terraform files — find and fix the bugs
2. Run `terraform init && terraform plan` to see errors
3. Fix the issues in main.tf
4. Run `terraform plan` to verify no errors remain
5. (Optional) `terraform apply` if using a real AWS account or KodeKloud Playground

**Requires:** Terraform installed. AWS credentials for apply (optional — you can learn from plan alone).
