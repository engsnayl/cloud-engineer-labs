# Hints — Cloud Lab 018: ECS Task Definition

## Hint 1 — Fargate requirements
Fargate requires: network_mode = "awsvpc", cpu and memory at task level, execution_role_arn set.

## Hint 2 — Container definition
Add portMappings: `[{ containerPort = 8080, protocol = "tcp" }]`. Add logConfiguration for CloudWatch.

## Hint 3 — CPU/Memory values
Add `cpu = "256"` and `memory = "512"` to the task definition (these are string values for Fargate).
