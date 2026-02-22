# Solution Walkthrough — ECS Task Definition Errors

## The Problem

An ECS service keeps failing to start tasks. The task definition has **five bugs** that prevent Fargate from launching the containers:

1. **Wrong network mode** — `network_mode = "bridge"` is for EC2 launch type. Fargate requires `"awsvpc"`.
2. **Missing execution role** — the `execution_role_arn` is commented out. Fargate needs the execution role to pull container images from ECR and send logs to CloudWatch.
3. **Missing CPU and memory** — Fargate requires `cpu` and `memory` to be set at the task definition level (not just on individual containers).
4. **Missing port mappings** — the container definition has no `portMappings`, so the service can't route traffic to the container.
5. **No log configuration** — without `logConfiguration`, container output goes nowhere. In production, you can't debug failed tasks without logs.

## Thought Process

When ECS tasks fail to start, an experienced cloud engineer checks:

1. **Network mode** — Fargate only supports `awsvpc`. Using `bridge` or `host` causes an immediate error.
2. **Execution role** — Fargate uses the execution role to pull images and push logs. Without it, the task can't even start.
3. **CPU/Memory** — Fargate requires specific CPU/memory combinations at the task level. Invalid combinations cause validation errors.
4. **Container configuration** — port mappings, log configuration, and health checks are essential for a working service.

## Step-by-Step Solution

### Step 1: Fix Bug 1 — Change network mode to awsvpc

```hcl
# BROKEN
resource "aws_ecs_task_definition" "payment_api" {
  family                   = "payment-api"
  network_mode             = "bridge"      # Wrong for Fargate!
  requires_compatibilities = ["FARGATE"]
}

# FIXED
resource "aws_ecs_task_definition" "payment_api" {
  family                   = "payment-api"
  network_mode             = "awsvpc"      # Required for Fargate
  requires_compatibilities = ["FARGATE"]
}
```

**Why this matters:** Fargate only supports `awsvpc` networking. In `awsvpc` mode, each task gets its own Elastic Network Interface (ENI) with a private IP address. The `bridge` mode uses Docker's built-in networking and is only available for EC2 launch type.

### Step 2: Fix Bug 2 — Add execution role

```hcl
resource "aws_ecs_task_definition" "payment_api" {
  family                   = "payment-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution.arn
}
```

**Why this matters:** The ECS execution role is used by the ECS agent (not your application) to:
- Pull container images from ECR
- Send container logs to CloudWatch Logs
- Retrieve secrets from Secrets Manager or SSM Parameter Store

Without it, Fargate can't pull the image and the task fails before your code even runs.

### Step 3: Fix Bug 3 — Add CPU and memory

```hcl
resource "aws_ecs_task_definition" "payment_api" {
  family                   = "payment-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  cpu                      = "256"
  memory                   = "512"
}
```

**Why this matters:** Fargate requires `cpu` and `memory` at the task definition level. These are strings (not numbers) and must be valid Fargate combinations:
- 256 CPU (.25 vCPU): 512, 1024, 2048 MB memory
- 512 CPU (.5 vCPU): 1024-4096 MB memory
- 1024 CPU (1 vCPU): 2048-8192 MB memory
- 2048 CPU (2 vCPU): 4096-16384 MB memory
- 4096 CPU (4 vCPU): 8192-30720 MB memory

Invalid combinations are rejected by AWS.

### Step 4: Fix Bugs 4 & 5 — Add port mappings and log configuration

```hcl
container_definitions = jsonencode([
  {
    name      = "payment-api"
    image     = "payment-api:latest"
    essential = true
    portMappings = [
      {
        containerPort = 8080
        protocol      = "tcp"
      }
    ]
    environment = [
      { name = "DB_HOST", value = "db.internal" },
      { name = "DB_PORT", value = "5432" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = "/ecs/payment-api"
        "awslogs-region"        = "eu-west-2"
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }
])
```

**Why this matters:**
- **Port mappings** — without `portMappings`, the service's load balancer can't route traffic to the container. In `awsvpc` mode, the `containerPort` is directly accessible on the task's ENI.
- **Log configuration** — `awslogs` driver sends container stdout/stderr to CloudWatch Logs. Without this, you have no visibility into what the application is doing — crucial for debugging failed tasks.

### Step 5: Add CloudWatch log group

```hcl
resource "aws_cloudwatch_log_group" "payment_api" {
  name              = "/ecs/payment-api"
  retention_in_days = 30
}
```

**Why this matters:** The log configuration references a CloudWatch log group. If it doesn't exist, the task fails to start. Creating it explicitly in Terraform ensures it exists and has a retention policy.

### Step 6: Validate

```bash
terraform validate
terraform plan
```

## Docker Lab vs Real Life

- **ECR for images:** In production, use ECR (Elastic Container Registry) instead of Docker Hub. The image reference would be `123456789012.dkr.ecr.eu-west-2.amazonaws.com/payment-api:v1.2.3` with specific version tags, never `latest`.
- **Task role vs execution role:** The execution role is for ECS infrastructure (pulling images, pushing logs). The task role is for your application code (accessing S3, DynamoDB, etc.). They're separate IAM roles with different trust policies.
- **Service discovery:** Production ECS services use AWS Cloud Map or Application Load Balancers for service discovery instead of hardcoded hostnames.
- **Auto-scaling:** ECS services support application auto-scaling based on CPU, memory, or custom metrics. Combined with Fargate, this provides fully serverless container scaling.
- **Secrets:** Instead of environment variables for database credentials, use `secrets` in the container definition to pull from Secrets Manager: `{ name = "DB_PASSWORD", valueFrom = "arn:aws:secretsmanager:..." }`.

## Key Concepts Learned

- **Fargate requires `awsvpc` network mode** — each task gets its own ENI and IP address. Bridge mode is EC2-only.
- **Execution role is mandatory for Fargate** — it pulls images and pushes logs. Without it, the task can't start.
- **CPU and memory must be valid Fargate combinations** — specified as strings at the task level. Invalid combinations are rejected.
- **Port mappings expose the container** — in `awsvpc` mode, `containerPort` is directly accessible on the task's IP. No `hostPort` mapping is needed.
- **Always configure logging** — without `logConfiguration`, you're flying blind. Production ECS tasks should always log to CloudWatch.

## Common Mistakes

- **Using `bridge` network mode with Fargate** — Fargate only supports `awsvpc`. This is the most common ECS Fargate error.
- **Confusing execution role and task role** — execution role = ECS agent infrastructure. Task role = your application permissions. Attaching the wrong policies to the wrong role causes either "can't pull image" or "can't access DynamoDB."
- **Invalid CPU/memory combinations** — 256 CPU with 4096 memory is invalid. Check the AWS docs for valid Fargate combinations.
- **Using `latest` tag in production** — `latest` is unpredictable. In production, use specific version tags for reproducible deployments.
- **Missing CloudWatch log group** — the log group must exist before the task starts. If it doesn't, the task fails. Create it in Terraform with `aws_cloudwatch_log_group`.
