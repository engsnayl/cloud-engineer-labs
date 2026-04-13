# Solution Walkthrough — Lab 077: ECS Task Definition Errors

## TLDR (Plain English)

An ECS service called `payment-api` can't start any tasks. Someone recently changed its task definition and broke it. Your job is to open the Terraform file, run `terraform plan`, follow the errors as they surface, fix each one, and then — critically — read the config with your own eyes to spot two issues that Terraform **won't** catch for you (missing port mappings and missing logging).

The five fixes, in plain terms:

1. **Switch the network mode to `awsvpc`.** Fargate only supports that mode. The file currently says `bridge`, which is for the old EC2 launch type.
2. **Uncomment the execution role line.** Fargate uses this IAM role to pull the container image and write logs on your behalf. Without it, the task can't even start.
3. **Add `cpu` and `memory` at the task level.** Fargate needs to know how much compute to allocate, specified as strings like `"256"` and `"512"`.
4. **Add `portMappings` to the container.** Without this, nothing can reach the container on a network port.
5. **Add `logConfiguration` to the container, and create a CloudWatch log group for it to write to.** Without logs you are flying blind the moment anything goes wrong.

Bugs 1, 2 and 3 will be handed to you directly by `terraform plan` error messages. Bugs 4 and 5 will not — `terraform plan` considers them optional. You only find those by reading the container definition critically and asking "is this actually production-ready?"

---

## The Ticket

You've been paged in on INCIDENT-AWS-009. The ticket says:

> ECS service "payment-api" stuck at 0 running tasks. Task attempts failing with multiple errors. Task definition was recently updated.

That's all you've got. You don't know what was changed, you don't know who changed it, and you don't know how many things are wrong. You `cd` into the lab directory and run `lab start 077`. You see a `main.tf` and a `CHALLENGE.md`. Time to start reasoning.

---

## Step 1 — Orient yourself before touching anything

Before you open `main.tf`, answer two questions:

1. **What am I looking at?** A Terraform project. The ticket says the task definition was "recently updated" — that tells me the drift is in code, not in the AWS console. I should be able to find the fault entirely in `main.tf`.
2. **What's the fastest feedback loop?** `terraform plan`. It will run through the config and tell me about any issues the AWS provider can detect statically. That's my first diagnostic tool.

Let's initialise the working directory and run a plan.

```bash
terraform init
terraform plan
```

**Command breakdown:**

| Command | What it does |
|---|---|
| `terraform init` | Downloads the AWS provider plugin and sets up the `.terraform/` working directory. Must run once before any other Terraform command. |
| `terraform plan` | Reads `main.tf`, validates the syntax and schema, and shows what Terraform would change if applied. Surfaces errors without making any real changes. |

Running plan is safe here — no AWS resources get created, no money is spent. It's pure read-and-validate.

---

## Step 2 — Read the first error carefully

`terraform plan` fails. The error points at the `aws_ecs_task_definition` block and complains about the network mode being incompatible with Fargate.

Before reaching for the fix, ask yourself:

1. **What is Terraform actually telling me?** That `network_mode = "bridge"` isn't valid when `requires_compatibilities = ["FARGATE"]`.
2. **Do I know why?** If not, now's the time to check. Fargate is serverless — AWS runs your container on infrastructure it manages. Each task gets its own Elastic Network Interface (ENI) with its own private IP. That networking model is called `awsvpc`. The `bridge` mode is Docker's built-in networking where containers share the host's network stack — that only works when you own the host, which on ECS means the EC2 launch type. Fargate can't offer `bridge` because there is no host for you to share.
3. **How do I verify the correct value?** The AWS provider documentation for `aws_ecs_task_definition` lists the allowed values for `network_mode`. Alternatively, the Terraform error message itself often names the valid option. For Fargate, it's `awsvpc`.

Open `main.tf` and make the change:

```hcl
network_mode = "awsvpc"
```

Re-run `terraform plan`. New error.

---

## Step 3 — Follow the next error

The next error complains that Fargate task definitions require an `execution_role_arn`.

The reasoning pathway:

1. **What's an execution role, and why does Fargate specifically need one?** On EC2 launch type, the EC2 instance has its own IAM instance profile and can pull images directly. On Fargate, there is no EC2 instance you control — the Fargate agent runs on AWS-managed infrastructure. That agent needs an IAM identity to do things on your behalf: pull the container image from ECR, fetch secrets, write logs to CloudWatch. That identity is the **execution role**. Without it, the Fargate agent has no permissions and the task can never start.
2. **Do I have one defined already, or do I need to create it?** Scroll the file. There's already an `aws_iam_role.ecs_execution` resource with the right trust policy (`ecs-tasks.amazonaws.com`) and the `AmazonECSTaskExecutionRolePolicy` attached. So the role exists — it just isn't wired up to the task definition.
3. **Where would I wire it?** The `aws_ecs_task_definition` block has an `execution_role_arn` argument. Looking at the file, I can see there's a **commented-out line** that looks suspiciously like exactly that:
   ```hcl
   # execution_role_arn       = aws_iam_role.ecs_execution.arn
   ```
   Someone has been here before and knew this was needed. Uncomment it.

Re-run `terraform plan`. New error.

---

## Step 4 — Follow the CPU/memory error

Next error: Fargate task definitions require `cpu` and `memory` at the task level.

Reasoning:

1. **Why at the task level and not the container level?** On Fargate, AWS bills you for the task's total allocated CPU and memory, not per-container. Fargate also only supports specific CPU/memory combinations (e.g. 256 CPU with 512 MB, 1024 CPU with 2048 MB, etc.). Those constraints only make sense at the task level, so that's where Fargate expects them.
2. **What values should I pick?** The smallest valid Fargate combination is `cpu = "256"` and `memory = "512"`. That's fine for a lab. Note they are **strings, not numbers** — that trips people up. It's `"256"` not `256`.
3. **Where do I look up the valid combinations?** AWS's [Fargate task definition docs](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-cpu-memory-error.html) list every allowed pair. If you pick an invalid combo, AWS rejects it at apply time.

Add to the task definition block:

```hcl
cpu    = "256"
memory = "512"
```

Re-run `terraform plan`. This time it succeeds. Green tick. Done, right?

**No. Stop and read the config.**

---

## Step 5 — The critical review (plan is not enough)

This is the bit that separates a mid-level engineer from someone who just chases errors. `terraform plan` has told you the config will apply. It has not told you the config is **correct**, or **safe**, or **production-ready**. Terraform only validates what AWS considers structurally required. Everything else is on you.

Before you close the ticket, re-read the `container_definitions` block with these questions in mind:

1. **How does traffic actually reach this container?** The service has `desired_count = 2` and a network configuration — so ECS will schedule two tasks in the `app` subnet. But the container itself has no `portMappings`. Nothing is listening on a declared port. Any load balancer, service discovery mechanism, or direct caller has no idea which port to hit. In `awsvpc` mode specifically, the `containerPort` is the port accessible on the task's ENI. Without it, the container is effectively unreachable.

   **This is Bug 4.** Terraform didn't catch it because `portMappings` is optional from a schema perspective — a container *can* exist without exposed ports (think of a worker that only talks to SQS). The provider can't know this one serves HTTP traffic.

2. **If this container crashes at 3am, how do I debug it?** There's no `logConfiguration`. The container will write to stdout/stderr, and that output will go straight to `/dev/null`. No CloudWatch, no file, no retention, nothing. When the on-call engineer runs `aws logs tail` to figure out why payments are failing, they get an empty result.

   **This is Bug 5.** Again, Terraform didn't flag it because logging is technically optional.

Both of these are things an experienced engineer catches on code review, not from compiler errors. They're also the kinds of things that make incidents much worse than they need to be.

---

## Step 6 — Add the port mapping and logging

Update `container_definitions` to include both:

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

**Breakdown of what you just added:**

| Field | What it means |
|---|---|
| `portMappings.containerPort` | The port the app listens on *inside* the container. In `awsvpc` mode this is also the port accessible on the task's ENI — there's no host-port mapping because there's no host. |
| `portMappings.protocol` | `tcp` or `udp`. HTTP services are always `tcp`. |
| `logConfiguration.logDriver` | `awslogs` is the CloudWatch Logs driver. Other options exist (splunk, fluentd, etc.) but `awslogs` is the default for AWS-native workloads. |
| `logConfiguration.options.awslogs-group` | The CloudWatch log group name to write to. Must exist *before* the task starts or the task fails. |
| `logConfiguration.options.awslogs-region` | Which region the log group lives in. Should match your provider region. |
| `logConfiguration.options.awslogs-stream-prefix` | Prefix for individual log streams inside the group. Each task gets its own stream named `<prefix>/<container>/<task-id>`. |

---

## Step 7 — Create the log group

You've told the container to log to `/ecs/payment-api`, but that log group doesn't exist yet. If you apply now, the first task will fail to start because the logging driver can't find its destination.

Add to `main.tf`:

```hcl
resource "aws_cloudwatch_log_group" "payment_api" {
  name              = "/ecs/payment-api"
  retention_in_days = 30
}
```

**Why `retention_in_days = 30`?** Without it, CloudWatch keeps logs forever, which quietly costs money. 30 days is a reasonable default for most services — long enough to investigate an incident retrospectively, short enough not to balloon storage.

---

## Step 8 — Verify

```bash
terraform plan
lab validate
```

**Command breakdown:**

| Command | What it checks |
|---|---|
| `terraform plan` | That the config is still syntactically and schema-valid after your edits. |
| `lab validate` | Runs the lab's validation script, which greps `main.tf` for each of the five fixes plus the log group resource — belt and braces against Terraform's blind spots. |

All checks should pass.

---

## Cleanup / Reset

This lab is plan-only — no AWS resources were ever created — so there's nothing to destroy.

To reset the lab to its broken state for another run:

```bash
cd ~/cloud-engineer-labs
git checkout -- <path-to-lab-077>/main.tf
```

Or re-clone / `git pull` fresh.

---

## Docker Lab vs Real Life

- **ECR, not Docker Hub.** Production task definitions use `123456789012.dkr.ecr.eu-west-2.amazonaws.com/payment-api:v1.2.3` with a specific version tag. Never `latest` — you lose the ability to roll back to a known-good image.
- **Task role vs execution role.** The **execution role** is for the ECS/Fargate agent itself (pulling images, pushing logs, fetching secrets). The **task role** is for your application code at runtime (reading from S3, writing to DynamoDB, calling other AWS APIs). They are separate IAM roles with different trust relationships and different policies. Mixing them up is one of the most common ECS IAM mistakes.
- **Secrets, not environment variables.** `DB_PORT = "5432"` as an env var is fine. `DB_PASSWORD = "hunter2"` as an env var is a resignation letter. Use the `secrets` block in the container definition to pull from Secrets Manager or SSM Parameter Store: `{ name = "DB_PASSWORD", valueFrom = "arn:aws:secretsmanager:..." }`.
- **Load balancers and service discovery.** Real payment APIs sit behind an Application Load Balancer or are registered with AWS Cloud Map. Neither is in this lab, but `portMappings` is the hook that both of those mechanisms depend on — no port mapping means no load balancer target, means no traffic.
- **Auto-scaling.** Fargate services scale via Application Auto Scaling, usually on CPU or memory utilisation. You'd add an `aws_appautoscaling_target` and `aws_appautoscaling_policy` — out of scope here, but the combination of Fargate + auto-scaling is what makes ECS "serverless containers".

---

## Key Concepts Learned

- **Fargate requires `awsvpc`.** Each task gets its own ENI and private IP. `bridge` and `host` modes only exist on EC2 launch type.
- **Execution role is not optional on Fargate.** The AWS-managed Fargate agent uses it to pull images and push logs. Without it, the task never starts.
- **CPU and memory live at the task level on Fargate, as strings.** Only specific combinations are valid — check the AWS docs when sizing a real workload.
- **`terraform plan` is a safety net with holes.** It catches schema and type errors but not missing-but-optional fields like `portMappings` and `logConfiguration`. You still have to read your own config.
- **Log groups must exist before tasks start.** Declare them in Terraform alongside the service that writes to them.

## Common Mistakes

- **Using `bridge` network mode with Fargate** — the most common Fargate error. Fargate only supports `awsvpc`.
- **Treating `cpu` and `memory` as numbers** — they're strings in Terraform. `cpu = 256` fails, `cpu = "256"` works.
- **Invalid CPU/memory combinations** — 256 CPU with 4096 MB memory is not a valid Fargate combo. AWS rejects these at apply time.
- **Confusing execution role with task role** — "can't pull image" means missing/broken execution role. "can't write to S3 from the app" means missing/broken task role.
- **Assuming `terraform plan` is enough** — it confirms Terraform is happy, not that the design is sound. Read your own config with a production mindset before you merge.
- **Forgetting the log group** — the log configuration references a log group that must exist. If you don't declare one, the task fails on first start with a logging driver error.
