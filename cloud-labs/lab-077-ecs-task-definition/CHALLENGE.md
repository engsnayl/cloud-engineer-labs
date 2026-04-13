Title: ECS Service Won't Start — Task Definition Errors
Difficulty: ⭐⭐⭐ (Advanced)
Time: 20-25 minutes
Category: AWS / ECS
Skills: ECS, task definitions, container definitions, Fargate, IAM execution roles, CloudWatch logging

## Scenario

The ECS service keeps failing to start tasks. The task definition has several configuration issues preventing containers from launching.

> **INCIDENT-AWS-009**: ECS service "payment-api" stuck at 0 running tasks. Task attempts failing with multiple errors. Task definition was recently updated.

## Objectives

1. Fix the ECS task definition so it is valid for Fargate
2. Ensure the execution role is properly wired up to the task definition
3. Ensure the container has the configuration needed to serve traffic and emit logs
4. `terraform validate` must pass
5. `terraform plan` must complete without errors
6. `lab validate` must pass all checks

## How to Use This Lab

1. Review the Terraform files — find and fix the bugs
2. Run `terraform init && terraform plan` to see errors
3. Fix the issues in `main.tf`
4. Run `terraform plan` again to verify no errors remain
5. Run `lab validate` to confirm all required fixes are in place
6. (Optional) `terraform apply` if using a real AWS account or KodeKloud Playground

**Requires:** Terraform installed. AWS credentials for apply (optional — you can learn from plan alone).
