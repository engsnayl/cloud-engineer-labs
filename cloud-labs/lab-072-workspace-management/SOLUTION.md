# Lab 072 — Terraform Workspace Confusion
## Solution Walkthrough

---

## Plain-English TLDR

Someone set up Terraform workspaces to manage staging and production environments — but forgot to actually make the configuration workspace-aware. The result? Every workspace deploys the exact same infrastructure: the same tiny instance size, the same environment label hardcoded to "staging", and the same minimal scaling settings. Production is running on staging-sized kit with staging tags on it.

There are three bugs, all in `main.tf`:

1. The instance type is hardcoded to `t3.micro` — it should be `t3.large` in production.
2. The `Environment` tag is hardcoded to `"staging"` — it should dynamically read the current workspace name.
3. The Auto Scaling Group uses `min=1, max=2` for every workspace — production needs higher limits.

The fix for all three is the same approach: introduce a `locals` block that maps each workspace name to its own configuration values, then replace every hardcoded value with a reference to that map.

---

## Before You Start — Run the Setup Script

This lab requires `staging` and `production` workspaces to exist before you begin investigating. Run the setup script once after changing into the lab directory:

```bash
cd cloud-labs/lab-072-workspace-management
bash setup.sh
```

The script will:
- Run `terraform init` if needed
- Create the `staging` and `production` workspaces
- Leave you in the `default` workspace ready to investigate

You should see:

```
Lab environment ready.
  Workspaces created: staging, production
  Active workspace:   default
```

---

## Background: What Are Terraform Workspaces?

Think of Terraform workspaces like named save slots in a video game. The game itself (your `.tf` code) is the same — but each save slot remembers a completely different state of the world. When you create a workspace called `staging`, Terraform creates a separate state file for it. When you switch to `production` and run `terraform apply`, Terraform tracks what it built there entirely independently.

A real-world analogy: imagine you're managing two offices — one in Manchester, one in London. The floor plan (your `.tf` files) is identical for both. But the furniture you've actually ordered and installed in each building is tracked separately. Terraform workspaces give you that separation — same blueprint, independent records of what's been built.

The key built-in variable is `terraform.workspace`. Wherever you use it in your configuration, Terraform substitutes the name of the currently active workspace — so if you're in the `production` workspace, `terraform.workspace` returns the string `"production"`. You can use that string to make decisions: tag resources with the right environment name, choose a different instance size, adjust scaling limits.

**Here's the critical thing that catches people out:** Terraform workspaces handle the *state* separation for you automatically — but they don't handle the *configuration* differences. That part is entirely your responsibility. If your `.tf` files never reference `terraform.workspace`, Terraform has no idea you want different behaviour per environment. It just deploys the same thing everywhere, every time.

To put that another way: creating a `production` workspace doesn't magically make your infrastructure production-grade. It just means Terraform is tracking it in a separate state file. If your code says `instance_type = "t3.micro"` with no conditions attached, production gets a `t3.micro` — same as staging, same as everything else. This lab is a real example of exactly that mistake.

---

## The Workspace Selection Habit

Before you run `terraform plan` or `terraform apply`, always confirm which workspace is active:

```bash
terraform workspace show
```

This prints just the name of the current workspace — one word. Make it a rule to run this before every apply. It takes two seconds and has saved many engineers from a very bad afternoon.

The workflow is always:

1. `terraform workspace select production` — switch first
2. `terraform workspace show` — confirm you're where you think you are
3. `terraform plan` / `terraform apply` — then act

There is no warning if you apply in the wrong workspace. Terraform will happily deploy production config to staging (or vice versa) without complaint.

---

## Real-Time Investigative Walkthrough

You've just been handed a ticket:

> **INCIDENT-TF-006:** Production is behaving like staging. Instances are undersized and all environment tags in AWS are showing the wrong environment name. We manage both environments with Terraform. Please investigate and fix.

You don't know exactly what's broken yet. Here's how you'd think through it.

---

### Step 1 — Get oriented: what does this codebase actually do?

Before touching anything, understand what you're dealing with. The first question an engineer asks on a cold ticket is: **what is this Terraform configuration managing, and how is it structured?**

```bash
ls -la
cat main.tf
```

Read through `main.tf`. You're looking for:
- What resources are being created?
- Is there any environment-specific logic at all?
- Are workspaces being used?

**What you'll find:** `main.tf` creates an EC2 instance, a launch template, an Auto Scaling Group, a VPC, and a subnet. No `locals` block. No `terraform.workspace` references anywhere.

**How would I know this matters?** The ticket says environment tags are wrong. If workspaces are in use but the config doesn't reference `terraform.workspace`, then every workspace is getting the same tags. That's the root cause. But keep reading before touching anything.

---

### Step 2 — Confirm which workspace you're in and what workspaces exist

Now that you've read the code, ask: **what workspace is currently active, and what workspaces are available?**

```bash
terraform workspace list
```

| Part | What it does |
|------|--------------|
| `terraform` | The Terraform CLI |
| `workspace` | Subcommand for managing workspaces |
| `list` | Lists all workspaces; the active one is marked with an asterisk (`*`) |

**What you'll see:**

```
* default
  production
  staging
```

The asterisk tells you which workspace is selected. The list confirms workspaces exist — so the team *intended* to separate environments. The fact that the code doesn't use `terraform.workspace` at all means the separation is only at the state level, not at the configuration level. The actual deployed resources are identical across workspaces.

---

### Step 3 — Find the specific hardcoded values

You've confirmed the problem exists at a conceptual level. Now be precise about where the bugs actually are in the file.

Read `main.tf` carefully and note:

**Bug 1 — Hardcoded instance type:**
```hcl
resource "aws_instance" "app" {
  instance_type = "t3.micro"   # same regardless of workspace
```

**Bug 2 — Hardcoded environment tag:**
```hcl
  tags = {
    Environment = "staging"    # always says "staging"
  }
```

**Bug 3 — Hardcoded scaling values:**
```hcl
resource "aws_autoscaling_group" "app" {
  min_size         = 1         # same for all environments
  max_size         = 2
  desired_capacity = 1
```

**How would I know these are wrong?** The ticket says environment tags are wrong and instance sizes look small. All three are the same problem: values that should vary by environment have been hardcoded. Now you know exactly what to fix.

---

### Step 4 — Build a workspace-aware locals block

The fix starts here. You need a lookup table that maps workspace names to their correct configuration values. In Terraform, this lives in a `locals` block.

**What is a locals block?**

A `locals` block lets you define values once and reuse them throughout your configuration. Think of locals as your own internal variables — not inputs from outside (those are `variables`), not outputs to expose (those are `outputs`), just values you compute once and reference many times inside your own config.

In this case, you're going to build a map (a lookup table) inside locals where each key is a workspace name and each value is a set of configuration options for that environment. Then, one line uses `terraform.workspace` to look up the right entry automatically.

Add this to the **top of `main.tf`**, before the resource blocks:

```hcl
locals {
  config = {
    default = {
      instance_type = "t3.micro"
      min_size      = 1
      max_size      = 2
      desired       = 1
    }
    staging = {
      instance_type = "t3.micro"
      min_size      = 1
      max_size      = 2
      desired       = 1
    }
    production = {
      instance_type = "t3.large"
      min_size      = 2
      max_size      = 10
      desired       = 2
    }
  }
  env = local.config[terraform.workspace]
}
```

**What's happening here, step by step:**

| Part | What it does |
|------|--------------|
| `locals { }` | Declares a block of local values — computed values you can reference throughout the config |
| `config = { ... }` | A map (lookup table) where each key is a workspace name |
| `default = { ... }` | Settings for the default workspace — always include this because Terraform always has a default workspace |
| `staging = { ... }` | Settings when the workspace is "staging" |
| `production = { ... }` | Settings when the workspace is "production" — note the larger instance type and wider scaling range |
| `env = local.config[terraform.workspace]` | The key line: `terraform.workspace` returns the current workspace name as a string, and `local.config[...]` uses it to look up the matching entry. The result is stored in `local.env`. |

**How would I know to do this?** This is the standard Terraform pattern for workspace-aware configuration. The alternative approaches (separate `.tfvars` files per environment, Terragrunt) are more complex — this is the simplest correct fix.

> **Lab vs Real Life — locals.tf:** In this lab the `locals` block lives inside `main.tf` to keep things simple. In a real team codebase you'll often see it in its own `locals.tf` file alongside `main.tf`, `variables.tf`, `outputs.tf`, and `providers.tf`. Each file has one concern. The code works identically either way — it's purely an organisation choice.

---

### Step 5 — Fix Bug 1: Replace hardcoded instance type

Now that `local.env` exists, replace the hardcoded `t3.micro` with a reference to it.

**Before:**
```hcl
resource "aws_instance" "app" {
  ami           = "ami-0c76bd4bd302b30ec"
  instance_type = "t3.micro"
```

**After:**
```hcl
resource "aws_instance" "app" {
  ami           = "ami-0c76bd4bd302b30ec"
  instance_type = local.env.instance_type
```

| Part | What it does |
|------|--------------|
| `local.env` | References the `env` local you defined — already contains the right config for the active workspace |
| `.instance_type` | The specific key within that map — returns `"t3.micro"` for staging, `"t3.large"` for production |

> **Lab vs Real Life — hardcoded AMI IDs:** The AMI ID here is hardcoded for simplicity — in real life you'd never do this. AMI IDs are region-specific (this one won't work outside `eu-west-2`), and they go stale when Amazon deprecates old images. In production you'd use a `data` source to look up the latest AMI dynamically at plan time, so it always resolves correctly regardless of region or age.

---

### Step 6 — Fix Bug 2: Replace hardcoded environment tag

**Before:**
```hcl
  tags = {
    Name        = "app-server"
    Environment = "staging"
  }
```

**After:**
```hcl
  tags = {
    Name        = "app-server-${terraform.workspace}"
    Environment = terraform.workspace
  }
```

| Part | What it does |
|------|--------------|
| `terraform.workspace` | Built-in Terraform variable — returns the current workspace name as a plain string |
| `"app-server-${terraform.workspace}"` | String interpolation — embeds the workspace name in the Name tag so you can tell instances apart in the AWS console |
| `Environment = terraform.workspace` | Tags the resource with the actual environment name rather than a hardcoded string |

Also apply the same fix to the launch template:

```hcl
resource "aws_launch_template" "app" {
  name_prefix   = "app-${terraform.workspace}"
  image_id      = "ami-0c76bd4bd302b30ec"
  instance_type = local.env.instance_type
}
```

---

### Step 7 — Fix Bug 3: Replace hardcoded ASG scaling values

**Before:**
```hcl
resource "aws_autoscaling_group" "app" {
  min_size         = 1
  max_size         = 2
  desired_capacity = 1
```

**After:**
```hcl
resource "aws_autoscaling_group" "app" {
  name             = "app-asg-${terraform.workspace}"
  min_size         = local.env.min_size
  max_size         = local.env.max_size
  desired_capacity = local.env.desired
  vpc_zone_identifier = [aws_subnet.app.id]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }
}
```

| Part | What it does |
|------|--------------|
| `local.env.min_size` | Minimum instances — 1 for staging, 2 for production |
| `local.env.max_size` | Maximum instances the ASG can scale to — 2 for staging, 10 for production |
| `local.env.desired` | The starting instance count when the ASG is created or reset |
| `name = "app-asg-${terraform.workspace}"` | Unique name per workspace — without this, workspaces would try to create ASGs with the same name, causing conflicts |

---

### Step 8 — The complete fixed main.tf

For reference, here is the full corrected file:

```hcl
locals {
  config = {
    default = {
      instance_type = "t3.micro"
      min_size      = 1
      max_size      = 2
      desired       = 1
    }
    staging = {
      instance_type = "t3.micro"
      min_size      = 1
      max_size      = 2
      desired       = 1
    }
    production = {
      instance_type = "t3.large"
      min_size      = 2
      max_size      = 10
      desired       = 2
    }
  }
  env = local.config[terraform.workspace]
}

provider "aws" {
  region = "eu-west-2"
}

resource "aws_instance" "app" {
  ami           = "ami-0c76bd4bd302b30ec"
  instance_type = local.env.instance_type

  tags = {
    Name        = "app-server-${terraform.workspace}"
    Environment = terraform.workspace
  }
}

resource "aws_autoscaling_group" "app" {
  name                = "app-asg-${terraform.workspace}"
  min_size            = local.env.min_size
  max_size            = local.env.max_size
  desired_capacity    = local.env.desired
  vpc_zone_identifier = [aws_subnet.app.id]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }
}

resource "aws_launch_template" "app" {
  name_prefix   = "app-${terraform.workspace}"
  image_id      = "ami-0c76bd4bd302b30ec"
  instance_type = local.env.instance_type
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "app" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
}
```

---

### Step 9 — Validate your changes

```bash
terraform validate
```

| Part | What it does |
|------|--------------|
| `terraform` | The Terraform CLI |
| `validate` | Parses and validates all `.tf` files in the current directory for syntax errors and basic configuration issues — does **not** contact AWS |

A clean validate doesn't prove the plan will succeed, but it catches typos and missing references before you waste time waiting for an API call.

---

### Step 10 — Run a plan in each workspace and compare

This is the proof step. Switch to production, confirm you're there, then plan:

```bash
terraform workspace select production
terraform workspace show
terraform plan
```

| Part | What it does |
|------|--------------|
| `terraform workspace select production` | Switches the active workspace to production |
| `terraform workspace show` | Confirms the active workspace before you do anything — good habit |
| `terraform plan` | Shows what would be deployed without actually doing it |

**What the production plan output looks like:**

```
# aws_instance.app will be created
  + resource "aws_instance" "app" {
      + instance_type = "t3.large"
      + tags = {
          + "Environment" = "production"
          + "Name"        = "app-server-production"
        }

# aws_autoscaling_group.app will be created
  + resource "aws_autoscaling_group" "app" {
      + desired_capacity = 2
      + max_size         = 10
      + min_size         = 2
      + name             = "app-asg-production"
```

**What to look for:**
- `instance_type = "t3.large"` in production, `"t3.micro"` in staging
- `min_size = 2`, `max_size = 10` in production, `min_size = 1`, `max_size = 2` in staging
- `Environment = "production"` / `Environment = "staging"` — no longer hardcoded

---

### Step 11 — Run the lab validator

```bash
lab validate 072
```

Expected output:

```
✅  Terraform configuration is valid
✅  Terraform plan completes without errors
Results: 2 passed, 0 failed
ALL CHECKS PASSED — WELL DONE!
```

---

## Cleanup / Reset

Revert `main.tf` to the broken starting state and clean up workspaces:

```bash
# Revert main.tf to broken state
git checkout -- main.tf

# Remove workspaces (must be in default first)
terraform workspace select default
terraform workspace delete staging
terraform workspace delete production
```

> **Note:** You can only delete a workspace if it has no resources in state. If you ran `terraform apply` in a workspace, run `terraform destroy` in that workspace first before deleting it.

The next time you want to run the lab from scratch, just run `bash setup.sh` again — it handles the cleanup and recreates everything cleanly.

---

## Lab vs Real Life

**Workspaces vs separate directories:** Many teams prefer giving each environment its own directory (or even its own repository) instead of using workspaces. Both approaches have separate state files — the difference is that separate directories let you have *different code* per environment, not just different variable values. Workspaces share the code. Separate directories don't.

**The wrong-workspace risk is real:** There's nothing in Terraform that stops you from running `terraform apply` in the wrong workspace. A distracted engineer could switch to `production` and forget about it, then run an apply that was meant for staging. Production teams typically add guardrails: CI/CD pipelines that enforce workspace selection, pre-apply scripts that print the workspace name and require confirmation, or separate AWS accounts per environment so credentials enforce the boundary.

**Terragrunt as an alternative:** Terragrunt is a wrapper around Terraform that provides a cleaner way to manage environments with DRY (Don't Repeat Yourself) config. Instead of a workspace locals map, each environment gets its own `terragrunt.hcl` with its own variable values and backend config. Many teams graduate to Terragrunt once their workspace pattern gets complex.

**Variable files per environment:** Another common alternative is `terraform apply -var-file=production.tfvars`. You maintain a `staging.tfvars` and `production.tfvars` with environment-specific values and pass the right one at apply time. This makes the environment values explicit and version-controlled, but relies on the engineer remembering to pass the correct flag.

**State isolation:** Each workspace has its own state file, but the state files share the same backend configuration (the same S3 bucket, for example). Some teams prefer completely separate backends per environment for stronger isolation — a corrupted state in staging can't touch production.

**AMI IDs in real life:** In this lab the AMI ID is hardcoded. In production you'd use a `data` source to look up the latest AMI dynamically at plan time — making the config region-agnostic and immune to AMI deprecation.

**locals.tf in real life:** In this lab the `locals` block lives in `main.tf`. In a real team codebase it typically gets its own `locals.tf` file, keeping `main.tf` focused purely on resources.

---

## Key Takeaways

- **`terraform.workspace` returns the current workspace name** — use it anywhere you need environment-specific behaviour
- **A locals map is the cleanest pattern** for mapping workspaces to configuration values — define once, reference everywhere
- **Always include a `default` entry** in your workspace map — the `default` workspace always exists and a missing map key causes a runtime error
- **Select your workspace first, then act** — `terraform workspace select production` before `terraform plan` or `terraform apply`
- **Use `terraform workspace show` as a sanity check** — confirm you're in the right workspace before every apply
- **Tag everything with `terraform.workspace`** — it's the only way to tell which environment owns a resource in the AWS console
- **Resource names must be unique per workspace** — prefix with `${terraform.workspace}` to avoid conflicts
- **Workspaces isolate state, not access** — separate AWS accounts or IAM policies are needed to truly prevent cross-environment mistakes
