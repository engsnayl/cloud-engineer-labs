# Solution Walkthrough — Lab 077: ECS Service Won't Start

## TLDR (Plain English)

An ECS service called `payment-api` is supposed to be running 2 tasks in cluster `production`. It is running zero. The on-call ticket says the task definition was recently changed. You inherit the mess.

This lab is **not** what it looks like at first glance. Both `terraform validate` and `terraform plan` report the configuration as healthy. There are no compile-time errors. If you trust those tools alone, you will close the ticket and walk away with a service that is still broken. The bugs in this lab only surface when you actually try to **run** the thing, and the only way to find them is to apply the configuration, watch what AWS does (or fails to do), and follow the error chain through several distinct layers.

There are three phases to the fix:

**Phase 1 — Task definition errors.** The task definition has Fargate-incompatible settings. `terraform apply` will fail with errors from the AWS API, one at a time, until you've fixed them all. Specifically: the network mode is wrong, there's no execution role, there's no CPU or memory specified at the task level.

**Phase 2 — The image and the network it needs.** Even with a valid task definition, the tasks won't start. The image reference points at a placeholder (`payment-api:latest`) that doesn't exist anywhere AWS can pull from, and the subnet has no route to the internet so even a real image couldn't be pulled. You'll fix the image to point at a real one and add the missing networking infrastructure (Internet Gateway, NAT Gateway, public subnet, route tables) so private workloads can reach external registries.

**Phase 3 — Production readiness.** With the service finally running, two things are still missing that nothing in AWS will complain about: there are no port mappings declared (so nothing can reach the container) and there's no logging configuration (so you can't see what the container is doing). These are code-review findings, not runtime errors. You'll add `portMappings`, `logConfiguration`, and a CloudWatch log group, then verify in CloudWatch that nginx is actually emitting logs.

The lab takes 40-50 minutes including NAT gateway provisioning waits. It costs a few pence in AWS charges (mostly the NAT gateway) and **must be cleaned up with `terraform destroy` at the end**.

---

## Background — What is ECS, What is Fargate, and Why Should You Care

### ECS in one sentence
**Elastic Container Service (ECS)** is AWS's container orchestrator — the system that decides which containers run where, restarts them when they crash, replaces them during deployments, and ties them to load balancers and auto-scaling rules.

### The four ECS concepts you need
- **Cluster** — a logical grouping of compute that runs tasks. Just a name and an ARN; it doesn't itself "do" anything.
- **Task definition** — the blueprint for a containerised workload. Defines which image to run, how much CPU and memory to give it, what environment variables to set, what network mode to use, what IAM roles to attach. **Task definitions are immutable in AWS** — you don't edit them, you create new revisions and point services at them.
- **Task** — a running instance of a task definition. May contain one container or several. Each task gets its own networking, IAM identity, and lifecycle.
- **Service** — the long-running controller that keeps N copies of a task definition alive. Handles rolling deployments, replacement of failed tasks, and registration with load balancers. The service is the thing you actually create when you want a workload to keep running.

### Fargate vs EC2 launch type
ECS has two ways to actually run your containers, and **the difference is the source of every bug in this lab**.

**EC2 launch type** — you provision a fleet of EC2 instances yourself, ECS schedules containers onto them. You see and pay for the instances. You patch the OS. You handle capacity planning. The container shares the host's network stack (this is what `bridge` networking means).

**Fargate launch type** — you don't provision anything. AWS runs your containers on infrastructure it manages. You don't see the underlying host, you can't SSH to it, you can't patch it. You pay per-task for the CPU and memory you allocate. Each task gets its own isolated networking via an Elastic Network Interface (ENI) attached directly to your subnet. This is what `awsvpc` mode means.

The five "bugs" in the original task definition are all symptoms of the same root cause: someone wrote a task definition that would have been fine for EC2 launch type and tried to run it on Fargate. Fargate has stricter requirements because there's no underlying host you control:

- **Network mode must be `awsvpc`** — there's no host network stack to share
- **Execution role is mandatory** — there's no EC2 instance profile to fall back on
- **CPU and memory must be at the task level** — Fargate bills per task, not per instance
- **Container needs explicit port mappings** — without a host network, the only way to reach a container port is through the task's own ENI

### Execution role vs task role — the mistake-magnet
This is one of the most commonly confused things in ECS.

- **Execution role** is for the ECS/Fargate **infrastructure**. The Fargate agent uses it to pull images from ECR, fetch secrets, and write logs to CloudWatch. Your application code never sees it.
- **Task role** is for your **application code at runtime**. If your service reads from S3 or writes to DynamoDB, it does so via the task role.

They are separate IAM roles with different trust policies. Confusing the two leads to errors like "can't pull image" (broken execution role) or "AccessDenied calling DynamoDB" (broken task role). This lab only uses the execution role; we'll mention task roles in the production notes at the end.

---

## The Ticket

You're on call. Your phone goes off at an unsociable hour with INCIDENT-AWS-009:

> ECS service "payment-api" in cluster "production" stuck at 0 running tasks. Task definition was recently updated. Page the on-call engineer.

That's the whole ticket. You don't know who changed what, when, or why. You don't know if the issue is the task definition itself, the surrounding infrastructure, or something further upstream. All you have is the symptom (zero tasks running) and a vague hint (the task definition was touched recently).

`cd` into the lab directory. Run `lab start 077`. You see a single `main.tf` and a `CHALLENGE.md`. Time to start.

---

## Phase 1 — Find What Terraform Thinks Is Wrong (Spoiler: Nothing)

### Step 1.1 — Initialise and plan

Before touching `main.tf`, get a baseline. Initialise the working directory and run a plan.

```bash
terraform init
terraform plan
```

**Command breakdown:**

| Command | What it does |
|---|---|
| `terraform init` | Downloads the AWS provider plugin and prepares the `.terraform/` working directory. Required once before any other Terraform command. |
| `terraform plan` | Reads `main.tf`, validates syntax and schema against provider definitions, and computes what would change if applied. Surfaces errors without making real changes. |

You expect a plan error. You don't get one. The plan is clean — `Plan: 8 to add, 0 to change, 0 to destroy`. Terraform considers this configuration valid.

**This is your first lesson, and arguably the most important one in the lab.** The AWS provider does almost no Fargate-specific validation at plan time. It checks that the HCL syntax is valid and that the resource attributes match the schema, but it doesn't know that `network_mode = "bridge"` is incompatible with `requires_compatibilities = ["FARGATE"]`. It doesn't know that Fargate requires an execution role. It doesn't know that Fargate requires CPU and memory at the task level. None of those constraints exist in the Terraform schema — they're enforced by the AWS API at apply time.

If you trust `terraform plan` as your only diagnostic, you stop here, declare the configuration healthy, and go back to bed. The ticket is still open. **Tools that pass mean nothing; only running the thing tells you the truth.**

### Step 1.2 — Apply and read the first error

```bash
terraform apply
```

Type `yes` when prompted. Watch what happens.

The VPC, subnet, security group, IAM role, and ECS cluster all create cleanly. Then the task definition fails with:

```
Error: creating ECS Task Definition (payment-api): operation error ECS:
RegisterTaskDefinition, https response error StatusCode: 400, ClientException:
Invalid setting for container 'payment-api'. At least one of 'memory' or
'memoryReservation' must be specified.
```

Stop and read this carefully — there's a subtlety here that distinguishes a junior fix from a senior fix.

AWS is saying "the *container* needs memory or memoryReservation". A junior engineer reads that and adds `memory = 512` to the container definition inside `container_definitions`. That would satisfy AWS. But it would not be the right fix.

The right fix is to set `cpu` and `memory` **at the task definition level**, because:

1. Fargate bills per task, not per container, so resource allocation belongs at the task level
2. Fargate only supports specific cpu/memory combinations at the task level (256/512, 256/1024, 512/1024, etc.) — these constraints don't exist at the container level
3. Once you set them at the task level, all containers in the task inherit from that allocation and the container-level setting becomes redundant

AWS's error message is misleading you toward the container-level fix because that's what its validator caught first. Reading past the literal error message to the underlying intent is the move that separates a code monkey from an engineer.

Open `main.tf` and add at the task definition level:

```hcl
cpu    = "256"
memory = "512"
```

Note these are **strings, not integers**. `cpu = 256` will fail Terraform validation. Save and re-apply.

### Step 1.3 — The next error: network mode

```
Error: creating ECS Task Definition (payment-api): ClientException: Fargate
only supports network mode 'awsvpc'.
```

This one is a gift — AWS literally tells you the correct value. ECS error messages are unusually friendly compared to most AWS services, which often give you opaque "ValidationException: Invalid parameter" responses with no hint what to change. When you see a clear "X only supports Y" message in ECS-land, just apply Y and move on. Don't overthink it.

The reasoning behind this constraint is worth knowing for interviews: `bridge` mode uses Docker's built-in networking, where containers share the host's network stack. On Fargate there is no host you control — there's nothing to share a network stack *with*. Fargate's solution is `awsvpc` mode, where each task gets its own dedicated Elastic Network Interface (ENI) attached to your VPC, with its own private IP. That's a more powerful model anyway: each task is a first-class network citizen.

Fix:
```hcl
network_mode = "awsvpc"
```

Save and re-apply.

### Step 1.4 — A wrinkle that AWS doesn't tell you about

When you re-apply now, the task definition creates successfully. The service creates successfully. Terraform says `Apply complete!`. **You are not done.**

Look at the apply output: there was never an error about the missing execution role. Why? Because the original `main.tf` had this line, commented out:

```hcl
# execution_role_arn       = aws_iam_role.ecs_execution.arn
```

Strictly speaking, an execution role is not *always* required on Fargate — it's only required if your task needs to do something that requires AWS API access on its behalf, like pulling a private ECR image or writing to CloudWatch. Since our current container definition has neither (no log configuration, and the image reference doesn't specify a private registry), Fargate accepts the task definition without one.

You'll fix this in Phase 3 when you add logging — at that point the task will need an execution role to write to CloudWatch, and you'll uncomment the line then. Worth flagging now: the commented-out line is a footprint of a previous engineer who knew the role was needed and either forgot to uncomment it or left it commented during testing. Code archaeology like this is how you reconstruct the history of a broken system.

### Phase 1 summary

You've cleared the AWS API's task definition validation. The Terraform apply succeeds. **But the original ticket said zero tasks running, not "task definition won't validate".** You've fixed a precondition, not the actual problem. Time to look at what's really going on.

---

## Phase 2 — The Service Is Created But Nothing Is Running

### Step 2.1 — Verify the symptom from the ticket

The most important habit when responding to an incident: check the exact symptom the ticket described, with your own eyes. Don't rely on Terraform's "Apply complete!" — that just means Terraform's idea of the world matches your code. It says nothing about whether the workload is actually running.

```bash
aws ecs describe-services \
  --cluster production \
  --services payment-api \
  --region eu-west-2 \
  --query 'services[0].{Desired:desiredCount,Running:runningCount,Pending:pendingCount}'
```

**Command breakdown:**

| Part | What it does |
|---|---|
| `aws ecs describe-services` | Asks the ECS API for the current state of one or more services |
| `--cluster production` | Which cluster the service lives in |
| `--services payment-api` | Which service(s) to describe — accepts multiple |
| `--region eu-west-2` | Required because your CLI default may differ |
| `--query` | JMESPath filter — pulls only the three counts we care about so you don't drown in JSON |

The output:
```json
{ "Desired": 2, "Running": 0, "Pending": 1 }
```

Desired 2, Running 0, Pending 1. Exactly what the ticket described. The service is trying to launch tasks but they're not coming up. This confirms the original symptom is still present even after the task definition fix.

### Step 2.2 — Look at the service events

ECS records every significant thing that happens to a service in an **events log** attached to the service object. This is the single most valuable diagnostic tool in ECS troubleshooting and most people never discover it exists. When a task fails to place, when a deployment starts or completes, when a target group registration fails — it all goes in service events.

```bash
aws ecs describe-services \
  --cluster production \
  --services payment-api \
  --region eu-west-2 \
  --query 'services[0].events[0:10]'
```

The output shows recent events. The most useful one will be a "was unable to place a task" entry with a `Reason:` field — that's where ECS tells you why the placement is failing.

If the events list shows only "has started 1 tasks" with no follow-up, the task is mid-launch and you need to wait. Re-poll after 30 seconds. If it still hasn't progressed, drop a level deeper to look at the task itself.

### Step 2.3 — Describe the task

Service events are layer 1 (orchestrator-level). When the orchestrator says "I tried to start a task" and that's the last thing it says, you need to descend to layer 2 — the task itself.

First, get the task ID:

```bash
aws ecs list-tasks \
  --cluster production \
  --service-name payment-api \
  --region eu-west-2
```

Then describe it. The full describe-tasks output is enormous, so use `--query` to pull only the diagnostic fields:

```bash
aws ecs describe-tasks \
  --cluster production \
  --tasks <task-id> \
  --region eu-west-2 \
  --query 'tasks[0].{LastStatus:lastStatus,DesiredStatus:desiredStatus,StoppedReason:stoppedReason,StopCode:stopCode,Containers:containers[*].{Name:name,LastStatus:lastStatus,Reason:reason}}'
```

**Fields to watch:**

| Field | Meaning |
|---|---|
| `LastStatus` | Where the task is in its lifecycle: `PROVISIONING` → `PENDING` → `ACTIVATING` → `RUNNING` → `STOPPING` → `DEPROVISIONING` → `STOPPED` |
| `StoppedReason` | Free-text reason ECS gives when a task stops. Common values include `CannotPullContainerError`, `ResourceInitializationError`, `Essential container in task exited` |
| `StopCode` | Categorised reason: `TaskFailedToStart`, `EssentialContainerExited`, `UserInitiated` |
| `Containers[].Reason` | Per-container reason, often more specific than the task-level reason |

If the task is `PENDING` with no `StoppedReason`, it hasn't failed yet — Fargate is still trying. Wait 30-60 seconds and re-check. Fargate retries image pulls aggressively (typically 7 times) before declaring failure, so silence can last a minute or more before resolving into a clear error.

For more depth on the task lifecycle, query the timing fields too:

```bash
aws ecs describe-tasks \
  --cluster production \
  --tasks <task-id> \
  --region eu-west-2 \
  --query 'tasks[0].{LastStatus:lastStatus,CreatedAt:createdAt,PullStartedAt:pullStartedAt,PullStoppedAt:pullStoppedAt,Connectivity:connectivity}'
```

**`PullStartedAt` / `PullStoppedAt`** are gold. If both are populated and they're milliseconds apart, image pull failed instantly — meaning the registry rejected the request immediately. If `PullStartedAt` is null, Fargate hasn't even gotten as far as trying to pull. If `PullStartedAt` is set and `PullStoppedAt` is null, the pull is in progress.

### Step 2.4 — Read the real error

Eventually the task transitions to `STOPPED` and `StoppedReason` populates with something like:

```
CannotPullContainerError: pull image manifest has been retried 7 time(s):
failed to resolve ref docker.io/library/payment-api:latest: failed to do
request: Head "https://registry-1.docker.io/v2/library/payment-api/manifests/latest":
dial tcp 44.210.47.137:443: i/o timeout
```

Read that error very carefully — it contains **two distinct problems** layered into one message:

**Problem A — `docker.io/library/payment-api`.** Fargate has resolved the bare image reference `payment-api:latest` to Docker Hub's official `library/` namespace. That's the same default behaviour as `docker pull` on your laptop: unqualified images get prefixed with `docker.io/library/`. Which means Fargate is looking for an *official Docker Hub library image* called `payment-api`. **No such image exists** — there's no official library image by that name. The image reference is a placeholder that means nothing in any registry on the public internet.

**Problem B — `dial tcp ... i/o timeout`.** Even if the image *did* exist, Fargate couldn't have found out, because the TCP connection to `registry-1.docker.io` timed out. The Fargate task is in a private subnet (`10.0.1.0/24`) with no route to the internet — no Internet Gateway, no NAT Gateway. There is no path from the task to Docker Hub. The "7 time(s)" retry count is Fargate trying repeatedly before giving up.

Both problems must be fixed for tasks to actually start. The image must point at something real, and the network must allow the task to reach the registry.

### Step 2.5 — Decide where to pull the image from

You have three realistic options for getting a real image:

1. **A real public image on Docker Hub** (e.g. `nginx:latest`). Requires the task to have outbound internet access, which means adding an Internet Gateway, a NAT Gateway, a public subnet for the NAT to live in, and route tables to wire it all together. Most production-realistic. Costs ~£0.04/hour for the NAT gateway.

2. **AWS Public ECR** (e.g. `public.ecr.aws/docker/library/nginx:latest`). A common myth (and I confess I believed it before testing) is that AWS Public ECR is reachable from Fargate tasks without internet access because it's an "AWS service". **It is not.** Public ECR is served from a public address (`public.ecr.aws`) and routing to it from a no-egress subnet still requires NAT or a VPC endpoint. There is no magic bypass.

3. **VPC endpoints for ECR** (`com.amazonaws.eu-west-2.ecr.api`, `com.amazonaws.eu-west-2.ecr.dkr`, plus an S3 gateway endpoint because ECR images are stored in S3 under the hood). This works without internet access but only for *private* ECR — not Public ECR or Docker Hub. Adds three endpoints (~£0.01/hour each) and is the right pattern when you're using ECR for your own images and want to avoid NAT charges entirely.

**For this lab we'll use option 1 with Public ECR as the image source** — that gives us a real, AWS-hosted nginx mirror without needing to deal with Docker Hub rate limits, while still requiring the NAT gateway pattern that mirrors real production deployments. We use Public ECR specifically so the lab works for users in regions where Docker Hub access is rate-limited or restricted.

### Step 2.6 — Fix the image reference

In `main.tf`, change:
```hcl
image = "payment-api:latest"
```
to:
```hcl
image = "public.ecr.aws/docker/library/nginx:latest"
```

This is the AWS-hosted public mirror of the official Docker library nginx image. It's the same image you'd get from Docker Hub, served from `public.ecr.aws` instead.

Save the file. Don't re-apply yet — there's no point until the network is also fixed.

### Step 2.7 — Add the missing networking

The current VPC has a single subnet, no Internet Gateway, no NAT. You need to add the standard "private workload with internet egress" pattern:

- An **Internet Gateway** attached to the VPC — the door to the internet
- A **public subnet** in a different CIDR range (`10.0.0.0/24`) which will host the NAT gateway
- An **Elastic IP** for the NAT gateway (NAT requires a stable public IP)
- A **NAT Gateway** in the *public* subnet (NAT itself must be reachable from the internet, so it lives in public)
- A **public route table** sending `0.0.0.0/0` to the IGW, associated with the public subnet
- A **private route table** sending `0.0.0.0/0` to the NAT, associated with the existing private subnet (`10.0.1.0/24`)

This is the standard architecture interview answer for "how do you give private workloads outbound internet without making them inbound-reachable from the public internet". Worth memorising.

Add the following to `main.tf` (the existing `aws_vpc.main`, `aws_subnet.app`, and `aws_security_group.app` resources stay; you're adding around them):

```hcl
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "eu-west-2a"
  map_public_ip_on_launch = true
}

resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id

  depends_on = [aws_internet_gateway.main]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.app.id
  route_table_id = aws_route_table.private.id
}
```

Also update the existing `aws_vpc.main` resource to add `enable_dns_support = true` and `enable_dns_hostnames = true` if they're not already there — Fargate needs DNS to resolve `public.ecr.aws`.

A few things worth knowing about this configuration:

- **`map_public_ip_on_launch = true`** on the public subnet means anything launched into it gets a public IP automatically. The NAT gateway needs this because NAT itself sits in public.
- **`depends_on = [aws_internet_gateway.main]`** on the NAT gateway is one of the rare cases where explicit `depends_on` is necessary. NAT requires the IGW to be attached to the VPC *before* it can attach properly, but Terraform can't infer this dependency from references alone because there's no reference between the two resources.
- **`domain = "vpc"`** on the EIP marks it as a VPC EIP rather than a classic EC2 EIP. Always use `vpc` in modern AWS — classic EC2 was deprecated years ago.

### Step 2.8 — Apply the networking and image fix together

```bash
terraform apply
```

Type `yes`. **The NAT gateway alone takes 90-120 seconds to create** — don't worry if the apply hangs at "Still creating..." for a couple of minutes. NAT is the slowest resource in this lab to provision, both up and down.

Total apply time: 2-3 minutes for everything to settle.

### Step 2.9 — Verify the service actually runs this time

After apply completes, wait another ~60 seconds for ECS to attempt fresh task placements through the now-functional networking, then re-check:

```bash
aws ecs describe-services \
  --cluster production \
  --services payment-api \
  --region eu-west-2 \
  --query 'services[0].{Desired:desiredCount,Running:runningCount,Pending:pendingCount}'
```

You want `Running: 2`. Then check the events for the magic line:

```bash
aws ecs describe-services \
  --cluster production \
  --services payment-api \
  --region eu-west-2 \
  --query 'services[0].events[0:5]'
```

The most recent event should read `(service payment-api) has reached a steady state.` That's ECS-speak for "I have the number of tasks you asked for, and I'm happy". Incident resolved. Pager goes silent.

### Phase 2 summary

You've now diagnosed the deeper truth behind INCIDENT-AWS-009: it wasn't "the task definition was broken", it was "the task definition was broken AND the surrounding network was broken AND the image reference was broken". This is closer to how real incidents actually look — multi-layered, multi-cause, and not solvable by reading any single error message in isolation.

**You also learned the layered diagnostic model:** service-level → task-level → container-level → image pull → network. Each layer has its own commands and its own error vocabulary. Real ECS troubleshooting is a top-down walk through those layers, never skipping one.

---

## Phase 3 — Production Readiness (The Things AWS Doesn't Catch)

The service is running. Two tasks are healthy. The ticket can be marked resolved. But before you hand it back, you do a final code review with production eyes — and you notice two things missing that would make this service genuinely operable in the real world.

### Step 3.1 — How is anyone supposed to reach this thing?

The container definition has no `portMappings`. nginx is listening on port 80 inside the container, but ECS doesn't know that. Without a declared port mapping:
- A load balancer can't register the task as a target
- Other services in the VPC can't reach the container by IP+port
- `awsvpc` mode has no way to expose the container port on the task ENI

In `awsvpc` mode, `containerPort` and `hostPort` are the same number — there's no host-port mapping like there would be on EC2 launch type, because there's no host. You just declare which port the container listens on, and that port is reachable on the task's ENI directly.

### Step 3.2 — How is anyone supposed to debug this thing?

The container definition has no `logConfiguration`. nginx is writing access logs and error logs to stdout/stderr — the standard pattern for containerised apps. With no log driver configured, that output goes straight to `/dev/null`. The container is fully invisible. When the next on-call engineer is paged at 3am because payments are failing, they have no logs to look at.

Production ECS services should *always* have logging configured. The standard setup is the `awslogs` driver pointing at a CloudWatch log group, with a stream prefix so each task gets its own stream named `<prefix>/<container>/<task-id>`.

### Step 3.3 — Add port mappings, logging, and the log group

Update the container_definitions block in `main.tf` to add `portMappings` and `logConfiguration`:

```hcl
container_definitions = jsonencode([
  {
    name      = "payment-api"
    image     = "public.ecr.aws/docker/library/nginx:latest"
    essential = true
    portMappings = [
      {
        containerPort = 80
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

**Field-by-field breakdown:**

| Field | What it means |
|---|---|
| `portMappings.containerPort` | The port the app listens on inside the container. In `awsvpc` mode this is also the port reachable on the task's ENI. |
| `portMappings.protocol` | `tcp` or `udp`. HTTP services are always `tcp`. |
| `logConfiguration.logDriver` | `awslogs` is the CloudWatch Logs driver. Other options exist (splunk, fluentd, fluent-bit) but `awslogs` is the default for AWS-native workloads. |
| `logConfiguration.options.awslogs-group` | Which CloudWatch log group to write to. **Must exist before the task starts** or the task fails. |
| `logConfiguration.options.awslogs-region` | Which region the log group lives in. Should match the provider region. |
| `logConfiguration.options.awslogs-stream-prefix` | Prefix for individual log streams inside the group. Each task creates a stream named `<prefix>/<container>/<task-id>`. |

Add the CloudWatch log group resource:

```hcl
resource "aws_cloudwatch_log_group" "payment_api" {
  name              = "/ecs/payment-api"
  retention_in_days = 30
}
```

`retention_in_days = 30` is important. Without it, CloudWatch keeps logs forever, which costs money and slowly accumulates noise. 30 days is a reasonable default — long enough to investigate yesterday's incident retrospectively, short enough not to balloon storage.

**Now uncomment the execution role**, because the awslogs driver needs the Fargate agent to have permission to write to CloudWatch. That permission comes from the execution role:

```hcl
execution_role_arn       = aws_iam_role.ecs_execution.arn
```

Without this, the next deployment will fail because Fargate can't authenticate to CloudWatch Logs.

You may also want to add an inbound rule to the security group allowing port 80 within the VPC, so other services in the VPC can reach the container:

```hcl
resource "aws_security_group" "app" {
  name   = "app-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

Note the ingress is locked to the VPC CIDR (`10.0.0.0/16`) rather than `0.0.0.0/0`. The container should not be reachable from the public internet directly — that would be the load balancer's job in a real deployment.

### Step 3.4 — Apply and verify the rolling deployment

```bash
terraform apply
```

This time the plan shows the task definition being replaced (because `container_definitions` changed, and task definitions are immutable so a new revision is created), the security group being modified, and the log group being created. Apply is fast — under a minute.

ECS will roll the deployment automatically: new tasks start with the new revision, wait until they're healthy, then drain the old ones. Wait ~60 seconds, then check:

```bash
aws ecs describe-services \
  --cluster production \
  --services payment-api \
  --region eu-west-2 \
  --query 'services[0].{Desired:desiredCount,Running:runningCount,Pending:pendingCount,TaskDef:taskDefinition}'
```

The `TaskDef` field should show the new revision number (probably `payment-api:4` or higher depending on how many revisions you've gone through). `Running` should be `2`.

### Step 3.5 — Verify logging in CloudWatch

This is the satisfying payoff. List the log streams in the new log group:

```bash
aws logs describe-log-streams \
  --log-group-name /ecs/payment-api \
  --region eu-west-2 \
  --query 'logStreams[*].{Name:logStreamName,LastEvent:lastEventTimestamp}'
```

You should see one log stream per running task, each named `ecs/payment-api/<task-id>`. The `LastEvent` timestamp tells you when the most recent event arrived — if it's recent (within the last minute or two), logs are flowing live.

Then tail the logs:

```bash
aws logs tail /ecs/payment-api --region eu-west-2 --since 10m
```

**Command breakdown:**

| Part | What it does |
|---|---|
| `aws logs tail` | Modern high-level CloudWatch Logs command, formats output nicely with timestamps and stream prefixes |
| `/ecs/payment-api` | The log group name (positional argument, not a flag) |
| `--since 10m` | Show only events from the last 10 minutes. Other valid values: `1h`, `30s`, ISO timestamps |
| `--follow` (optional) | Stream new events live, like `tail -f`. Press Ctrl+C to stop |

You should see nginx's startup output from both containers — the `docker-entrypoint.sh` running its initialisation scripts, the `nginx/1.x.x` version line, the `start worker process` messages. **That output is coming from nginx running on AWS-managed Fargate infrastructure, captured by the awslogs driver, sent to CloudWatch, and displayed on your terminal.** End-to-end observability, working.

A useful detail you might notice in the logs: there's a line like `OS: Linux 5.10.x amzn2.x86_64`. That's the host kernel underneath your container — Amazon Linux 2. It's a glimpse of the infrastructure you don't normally see, and a useful bit of trivia for interview questions about "what is Fargate actually running on".

### Phase 3 summary

You've added the two things AWS never warned you about: port declaration so the container is reachable, and logging so the container is observable. These are code-review findings, not runtime errors. **The lesson is that `terraform plan` and "Apply complete!" are not the same thing as "production-ready".** A senior engineer reads their own config with a production mindset before merging, asking questions like "how does this get reached?", "how do I debug this when it breaks?", and "what would I want to see in CloudWatch at 3am?".

---

## Cleanup — DO NOT SKIP THIS

This lab provisions real AWS resources that cost real money, primarily the NAT gateway (~£0.04/hour) and the Elastic IP (~£0.005/hour while attached to NAT). Total cost while running is small but non-zero and accumulates if left running overnight.

**Always destroy before logging off:**

```bash
terraform destroy
```

Type `yes` when prompted. The destroy takes 3-5 minutes total, mostly because of the NAT gateway teardown which takes 1-2 minutes. Watch for `Destroy complete! Resources: XX destroyed.` at the end.

**If destroy hangs on a subnet for more than 2 minutes**, see the "Lab Notes" section below for the stuck-apply / stuck-destroy pattern and how to recover.

---

## Lab Notes (Real Things That Went Wrong)

### The Public ECR myth
There's a widely-held belief (which I held myself before testing) that AWS Public ECR is reachable from Fargate tasks in private subnets without NAT, because it's "an AWS service". **It is not.** Public ECR is served from a public address (`public.ecr.aws`) and routing to it from a no-egress subnet still requires either a NAT gateway, an Internet Gateway with a public IP on the task, or a VPC endpoint. There is no magic bypass for Public ECR specifically.

VPC endpoints for ECR exist (`com.amazonaws.eu-west-2.ecr.api`, `com.amazonaws.eu-west-2.ecr.dkr`, plus the S3 gateway endpoint), but they only work for private ECR (your account's images), not Public ECR. If you want to avoid NAT charges entirely, the right pattern is to mirror the public images you need into your private ECR and use the VPC endpoints to reach them.

### The `payment-api:latest` placeholder error
The original image reference fails for two layered reasons that are easy to confuse:
1. The image doesn't exist anywhere
2. The network can't reach any registry to find out

The error message contains both clues but you have to read carefully. `failed to resolve ref docker.io/library/payment-api:latest` is the "image doesn't exist" half. `dial tcp ...: i/o timeout` is the "network can't reach the registry" half. Fix one without the other and you'll just fail differently.

### Subnet replacement during a live deployment
If you ever modify a `forces replacement` attribute on a subnet that has running ECS tasks attached, **scale the service to 0 first**. The pattern is:

```bash
aws ecs update-service \
  --cluster production \
  --service payment-api \
  --desired-count 0 \
  --region eu-west-2
```

Wait until `runningCount: 0`, then run your `terraform apply`. If you don't do this, Terraform will sit forever waiting for the subnet to be empty while ECS keeps spawning new tasks into it that re-create ENIs, deadlocking the destroy. The symptom is `Still destroying... [10m elapsed]` on a subnet that should take 5 seconds.

If you ever see `InvalidSubnetID.NotFound` in the service events, that's ECS attempting to place a task in a subnet ID that Terraform deleted out from under it — same root cause, same fix.

### `terraform plan` doesn't catch Fargate constraints
The AWS Terraform provider does not validate Fargate-specific requirements at plan time. Every error in Phase 1 of this lab surfaces only at apply time, from the AWS API. The lesson: **never trust `terraform plan` as your only diagnostic for AWS-provider-specific runtime constraints**. The provider knows the schema, not the semantics.

### NAT gateway timing
NAT gateways take 90-120 seconds to create and 60-90 seconds to destroy. This is the slowest resource in the lab and it's not a hang — just be patient. If you Ctrl+C during a NAT gateway operation, you'll leave it in a weird state and have to manually clean up.

### `lab validate` validator notes
Originally `validate.sh` only checked that `terraform validate` and `terraform plan` succeeded. Both pass on a totally broken configuration in this lab, so those checks were strengthened with grep-based assertions against `main.tf` for each required fix: network mode, execution role, cpu, memory, image change, internet gateway, NAT, EIP, route tables, route table associations, port mappings, log configuration, log group. The validator now reflects what actually needs to be present rather than what Terraform happens to be happy with.

---

## Real-World Patterns

### ECR vs Docker Hub for production images
Production task definitions should never reference `:latest`. Always pin to a specific version tag like `payment-api:v1.2.3`. `:latest` is non-deterministic — the image referenced by the tag changes whenever someone pushes — which means rolling back to "yesterday's working version" is literally impossible.

For private images, use ECR with a fully qualified reference: `123456789012.dkr.ecr.eu-west-2.amazonaws.com/payment-api:v1.2.3`. The Fargate execution role's default policy (`AmazonECSTaskExecutionRolePolicy`) grants ECR pull permissions automatically, so no extra IAM work needed.

### Task role for application IAM
This lab only uses the execution role. In production, your application probably needs to call AWS APIs at runtime — read S3 objects, write to DynamoDB, fetch secrets. That's the **task role**, separate from the execution role:

```hcl
resource "aws_iam_role" "ecs_task" {
  name = "ecs-task-role"
  # ... trust policy ...
}

resource "aws_ecs_task_definition" "payment_api" {
  task_role_arn      = aws_iam_role.ecs_task.arn
  execution_role_arn = aws_iam_role.ecs_execution.arn
  # ...
}
```

The task role's policies grant your application permissions. The execution role's policies grant the Fargate agent permissions. Two roles, two trust policies, two purposes.

### Secrets, not environment variables
The current task definition has `DB_HOST` and `DB_PORT` as plain environment variables. That's fine for non-sensitive config. For secrets like `DB_PASSWORD`, use the `secrets` block to pull from Secrets Manager or SSM Parameter Store at task start:

```hcl
secrets = [
  {
    name      = "DB_PASSWORD"
    valueFrom = "arn:aws:secretsmanager:eu-west-2:123456789012:secret:prod/payment-api/db-password"
  }
]
```

The execution role needs `secretsmanager:GetSecretValue` permission for the specific ARN. The secret is fetched at task start time and injected as an environment variable — your application code doesn't need to know it came from Secrets Manager.

### Load balancers and target groups
Real services sit behind an Application Load Balancer. Add a `load_balancer` block to the service:

```hcl
resource "aws_ecs_service" "payment_api" {
  # ...
  load_balancer {
    target_group_arn = aws_lb_target_group.payment_api.arn
    container_name   = "payment-api"
    container_port   = 80
  }
}
```

The `container_port` here matches the `containerPort` you declared in `portMappings`. This is the link that ties the load balancer's target group to your task's ENI — without `portMappings` declared, this wouldn't work, which is part of why port mappings matter even when AWS doesn't enforce them.

### Auto-scaling
Fargate services scale via Application Auto Scaling, usually on CPU or memory utilisation:

```hcl
resource "aws_appautoscaling_target" "payment_api" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.payment_api.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = 2
  max_capacity       = 20
}

resource "aws_appautoscaling_policy" "payment_api_cpu" {
  name               = "cpu-tracking"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.payment_api.resource_id
  scalable_dimension = aws_appautoscaling_target.payment_api.scalable_dimension
  service_namespace  = aws_appautoscaling_target.payment_api.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value = 70.0
  }
}
```

The combination of Fargate + Application Auto Scaling is what makes ECS "serverless containers" — capacity scales automatically and you pay only for what runs.

---

## Key Concepts Learned

- **Fargate requires `awsvpc` networking.** Each task gets its own ENI and private IP. `bridge` and `host` modes only exist on EC2 launch type.
- **`terraform plan` doesn't catch Fargate runtime constraints.** Every Phase 1 error in this lab surfaces only at apply time, from the AWS API. Plan validates schema, not semantics.
- **CPU and memory live at the task level on Fargate, as strings.** Only specific combinations are valid — `256/512`, `512/1024`, etc. Check AWS docs for the full matrix.
- **The execution role is the Fargate agent's identity, not your application's.** It pulls images, writes logs, and fetches secrets. Confusing it with the task role is one of the most common ECS IAM mistakes.
- **ECS troubleshooting is a layered onion: service → task → container → image pull → network.** Each layer has its own commands and its own error vocabulary. `describe-services` for layer 1, `describe-tasks` for layer 2, container reasons for layer 3, `StoppedReason` for layer 4, network and route inspection for layer 5.
- **Service events are the most useful diagnostic in ECS** and most learners never discover them. Always check `events[]` when a service isn't behaving.
- **Public ECR is not magic** — it lives on the public internet and needs the same NAT or VPC endpoint pattern as Docker Hub.
- **Port mappings and logging are optional from AWS's perspective but mandatory from yours.** A senior engineer adds both before merging, even though nothing in Terraform will complain if you don't.
- **CloudWatch log groups must exist before tasks reference them.** Declare them in Terraform alongside the service that writes to them.
- **NAT gateways are slow.** 90-120 seconds to create, 60-90 seconds to destroy. Plan accordingly.

## Common Mistakes

- **Trusting "Apply complete!"** as proof that the workload is running. It only proves Terraform's state matches your code.
- **Reading AWS error messages literally** instead of asking "what's the underlying intent". The container-level memory error in Phase 1 is the canonical example.
- **Treating CPU/memory as numbers in Terraform.** They're strings. `cpu = 256` fails; `cpu = "256"` works.
- **Confusing execution role with task role.** "Can't pull image" or "can't write logs" → execution role. "AccessDenied calling DynamoDB" → task role.
- **Modifying running infrastructure with force-replacement attributes.** Scale the workload to 0 first, or expect deadlocks.
- **Forgetting `terraform destroy`.** NAT gateway charges accrue continuously. Always destroy before logging off.
- **Hitting Ctrl+C during a NAT gateway operation.** It leaves the resource in a weird state. Wait it out.
- **Believing Public ECR works without NAT.** It doesn't.
