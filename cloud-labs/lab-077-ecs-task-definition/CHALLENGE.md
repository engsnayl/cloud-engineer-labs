Title: ECS Service Won't Start — Task Definition and Beyond
Difficulty: ⭐⭐⭐⭐ (Expert)
Time: 40-50 minutes
Category: AWS / ECS
Skills: ECS, Fargate, task definitions, IAM execution roles, VPC networking, NAT gateways, CloudWatch Logs, incident response

## Scenario

The ECS service keeps failing to start tasks. The task definition was recently updated, but the issue may run deeper than that — `terraform plan` and `terraform validate` both report the configuration as healthy, yet the tasks are not running.

> **INCIDENT-AWS-009**: ECS service "payment-api" in cluster "production" stuck at 0 running tasks. Task definition was recently updated. Page the on-call engineer.

## Objectives

1. Diagnose why ECS tasks are failing to start, using AWS CLI as your primary tool
2. Fix all task definition issues so the configuration is valid for Fargate
3. Address any infrastructure issues preventing tasks from pulling their image
4. Ensure the running service is observable (logs accessible) and reachable (ports declared)
5. `terraform validate` and `terraform plan` must complete cleanly
6. `lab validate` must pass all checks
7. The service must reach steady state with the desired number of tasks running
8. CloudWatch must contain logs from the running containers
9. All AWS resources must be destroyed cleanly at the end

## How to Use This Lab

1. Run `terraform init` and read `main.tf` — the engineer who broke this is gone, you have nothing but the code and the ticket
2. Apply the configuration and follow the errors AWS gives you, layer by layer
3. Use `aws ecs describe-services`, `aws ecs describe-tasks`, and the service event log as your diagnostic tools — Terraform alone will not be enough for this lab
4. When you think the issue is fixed, verify by reaching steady state, not by trusting `Apply complete`
5. Check CloudWatch to confirm the containers are actually running and emitting logs
6. Run `terraform destroy` when finished — this lab incurs real (small) AWS charges while running

**Requires:** Terraform installed, AWS credentials configured, permissions to create VPC/ECS/IAM/CloudWatch resources in the target account.

**Cost note:** This lab provisions a NAT Gateway and Elastic IP, both of which charge by the hour. Total cost for completing the lab in one sitting is typically under £0.20. **Always run `terraform destroy` before logging off.**
