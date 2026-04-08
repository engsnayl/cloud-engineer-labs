# Lab 074 — Terraform Conditional Logic Bugs
## Solution Walkthrough

---

## Plain-English TLDR

You've been handed a Terraform configuration that's supposed to behave differently depending on which environment it's deployed to — staging vs production — and whether certain features like monitoring are switched on. The ticket says resources are appearing where they shouldn't, and missing where they should be.

The problems all boil down to **conditional logic that's been written backwards or incorrectly**. Four bugs, four fixes:

1. A bastion host (a jump-box for SSH access) is being created in production, but should only exist in staging. The condition is inverted.
2. A `for_each` loop is trying to iterate over a list, but `for_each` doesn't accept lists. You need to convert the list to a set first using `toset()`.
3. A dynamic block that creates firewall rules is using `.key` (which gives you the position in the list: 0, 1, 2) instead of `.value` (which gives you the actual port number: 80, 443, 8080). The rules are being created for ports 0, 1, and 2 — which are meaningless port numbers.
4. A CloudWatch alarm that's supposed to be created when monitoring is enabled is doing the opposite — because the 1 and 0 in the condition are swapped.

**The fix pattern for all four:** read the conditional carefully, verify what it's actually doing, and correct it. No infrastructure redesign needed — just logic corrections in `main.tf`.

---

## Understanding the Broken main.tf — Line by Line

Before you can debug this configuration, you need to understand what it's trying to do and what concepts it introduces. Here's a full walkthrough of the broken file as it exists when you arrive.

---

### The provider block

```hcl
provider "aws" {
  region = "eu-west-2"
}
```

This tells Terraform which cloud provider to use and which region to deploy into. `eu-west-2` is AWS London. Every resource defined in this file will be created in that region unless overridden. This block is fine — no bug here.

---

### Variable declarations

```hcl
variable "environment" {
  default = "production"
}

variable "enable_monitoring" {
  default = true
}
```

These are **input variables** — they're how you pass configuration values into a Terraform setup without hardcoding them into the resource definitions. You can think of them like settings dials.

- `environment` controls which environment this deployment represents. Its default value is `"production"`.
- `enable_monitoring` is a true/false switch — a feature flag — for whether a CloudWatch alarm should be created. It defaults to `true`.

The word `default` means: if nobody passes a value in from outside (via a `.tfvars` file or command-line argument), use this value. In this lab, there's no `.tfvars` file — so these defaults are the values that will be used. That matters for every conditional you'll check later.

**In a real project** these variables would typically be declared in `variables.tf` and the values set in `terraform.tfvars`. In this lab they're colocated in `main.tf` for simplicity. The `variables.tf` file exists but is empty.

---

### The bastion host (Bug 1)

```hcl
resource "aws_instance" "bastion" {
  count         = var.environment == "production" ? 1 : 0
  ami           = "ami-0c76bd4bd302b30ec"
  instance_type = "t3.micro"
  tags = { Name = "bastion-host" }
}
```

**What this is trying to do:** Create an EC2 instance to act as a bastion host — an SSH jump box that engineers use to hop into private instances within the VPC. The intent is that this should only exist in staging (where engineers need direct access for debugging), not in production.

**New concept — `count`:** Normally a resource block creates exactly one resource. Adding `count = N` tells Terraform to create N copies of it. `count = 0` means don't create it at all. `count = 1` means create one. This is how you make a resource optional.

**New concept — the ternary expression:** The `count` value here isn't a plain number — it's a conditional expression:

```hcl
count = var.environment == "production" ? 1 : 0
```

Read this as: **"if `var.environment` equals `"production"`, use `1`. Otherwise use `0`."**

The format is always: `condition ? value_if_true : value_if_false`

- `var.environment == "production"` — this is the condition. It asks: is the environment variable equal to the string "production"?
- `? 1` — if yes, count is 1 (create the bastion)
- `: 0` — if no, count is 0 (skip it)

**The bug:** The condition is the wrong way round. It creates the bastion when the environment is production, and skips it everywhere else. The intent is the opposite — staging only.

**`ami` and `instance_type`:** These are the settings for the EC2 instance itself. The AMI is the machine image (the operating system), and `t3.micro` is the size. Not relevant to the bug, but you'll see these in every EC2 resource.

---

### The subnet CIDR variable

```hcl
variable "subnet_cidrs" {
  default = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}
```

This variable holds a list of three IP address ranges — one for each subnet that will be created. A CIDR block like `"10.0.1.0/24"` defines a range of IP addresses within the VPC.

**New concept — a list:** The square brackets `[ ]` with comma-separated values make this a **list** in Terraform. A list is an ordered collection of items. The order matters — item 0 is `"10.0.1.0/24"`, item 1 is `"10.0.2.0/24"`, and so on.

This variable is fine. The bug is in how it gets *used* — which you'll see next.

---

### The VPC

```hcl
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}
```

This creates a Virtual Private Cloud — a private, isolated network in AWS inside which all the other resources (subnets, instances, security groups) will live. The `10.0.0.0/16` range is the overall IP space for the whole VPC. The subnets will each get a smaller slice of that range. No bug here.

---

### The subnets (Bug 2)

```hcl
resource "aws_subnet" "app" {
  for_each   = var.subnet_cidrs
  vpc_id     = aws_vpc.main.id
  cidr_block = each.value
}
```

**What this is trying to do:** Create one subnet for each CIDR in the `subnet_cidrs` list — so three subnets in total, each with its own IP range, all inside the VPC.

**New concept — `for_each`:** Where `count` creates N identical copies of a resource, `for_each` creates one resource *per item in a collection*, and each one can be configured differently. Here it's trying to loop over the three CIDRs and create a separate subnet for each one.

Inside the block, `each.value` refers to the current item being processed — the CIDR string for that iteration.

**The bug:** `for_each` has a strict requirement — it only accepts a **set** or a **map**. It does not accept a **list**. The variable `subnet_cidrs` is a list. When Terraform encounters this, it stops and throws a type error:

```
The given "for_each" argument value is unsuitable: the "for_each" argument
must be a map, or set of strings, and you have provided a value of type tuple.
```

You'll notice the error says **tuple** rather than **list**. These mean the same thing in this context — Terraform uses the word tuple internally for what most people call a list. Don't let that terminology trip you up.

**Why doesn't `for_each` accept lists?** This is explained in full in the section below. The short version: lists are ordered by position (0, 1, 2), and that's unstable for Terraform's state tracking. Sets are identified by value, which is stable. `for_each` requires that stability.

---

### Understanding lists, sets, tuples, and why for_each won't accept a list

This section starts from scratch. No assumed knowledge.

**What is a list?**

A list is just a collection of items in a specific order. In Terraform:

```hcl
["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
```

The items are in positions 0, 1, and 2. The order is fixed. If you ask "what's at position 0?", the answer is always `"10.0.1.0/24"`.

**What is a set?**

A set is also a collection of items, but with two key differences:

1. **No duplicates** — each item can only appear once
2. **No meaningful order** — items aren't numbered by position

Instead of "item at position 0", a set identifies items by their actual value. So `"10.0.1.0/24"` is its own identifier.

**What is a tuple?**

A tuple is Terraform's internal name for what most people call a list. When you write `["a", "b", "c"]` in Terraform, it stores it as a tuple. The error message says "tuple" — but it means "list". Same thing. This is just Terraform's terminology being confusing.

**What is a map?**

A map is a collection of key-value pairs — like a dictionary. Each item has a name (key) and a value. For example:

```hcl
{
  web  = "10.0.1.0/24"
  app  = "10.0.2.0/24"
  data = "10.0.3.0/24"
}
```

Here "web", "app", and "data" are the keys, and the CIDRs are the values.

**Why does `for_each` refuse to accept a list?**

When Terraform creates a resource using `for_each`, it needs to give each copy a stable, unique name in its state file. The state file is how Terraform remembers what it created — it's like a record book. Each entry needs a permanent identifier.

If you use a list, Terraform would have to identify each resource by its position — `aws_subnet.app[0]`, `aws_subnet.app[1]`, `aws_subnet.app[2]`.

Now imagine you remove the first CIDR from the list. Everything shifts:
- What was at position 1 is now at position 0
- What was at position 2 is now at position 1

Terraform looks at its state and thinks: "the thing at position 0 has changed — I need to destroy and recreate it." It would try to recreate subnets that don't need changing, just because the numbering shifted. That's dangerous in production.

If you use a set instead, each resource is identified by its actual value — `aws_subnet.app["10.0.1.0/24"]`. Remove the first CIDR and the other two keep their identities. Nothing gets unnecessarily recreated.

**What is `toset()` doing?**

`toset()` is a built-in Terraform function that converts a list into a set:

```hcl
toset(["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"])
```

This takes your list and produces a set from it. After conversion:
- Terraform can use it with `for_each`
- Each subnet is identified by its CIDR value, not its position
- Removing or reordering CIDRs won't cause unnecessary resource destruction

The only thing `toset()` can't preserve is order — but `for_each` doesn't care about order, so that doesn't matter here.

---

### The security group (Bug 3)

```hcl
resource "aws_security_group" "app" {
  name   = "app-sg"
  vpc_id = aws_vpc.main.id

  dynamic "ingress" {
    for_each = [80, 443, 8080]
    content {
      from_port   = ingress.key
      to_port     = ingress.key
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
}
```

**What this is trying to do:** Create a security group (a firewall) with three inbound rules — one allowing traffic on port 80 (HTTP), one on port 443 (HTTPS), and one on port 8080 (a common alternative HTTP port). The rules are generated dynamically from a list of port numbers rather than being written out three times.

**New concept — a security group:** In AWS, a security group is a virtual firewall that controls which network traffic is allowed in and out of a resource. Each inbound rule (`ingress`) says: allow traffic coming in on this port, using this protocol, from these IP addresses. `"0.0.0.0/0"` means "from anywhere on the internet".

**New concept — a `dynamic` block:** Normally if you want three ingress rules, you'd write three separate `ingress { }` blocks. A `dynamic` block lets you generate those blocks automatically by looping over a list. It's like a for loop that writes HCL for you.

The `for_each` inside a `dynamic` block works similarly to resource-level `for_each` — it iterates over each item in the collection. For each item, the `content { }` block defines what gets generated.

Inside the `content` block, you reference the current item using the block's name as a prefix:
- `ingress.key` — the **position** of the current item in the list (0, 1, 2)
- `ingress.value` — the **actual value** of the current item (80, 443, 8080)

**The bug:** The code uses `ingress.key` for both `from_port` and `to_port`. So instead of creating rules for ports 80, 443, and 8080, it creates rules for ports 0, 1, and 2. You can see this clearly in the plan output:

```
+ ingress = [
    + { from_port = 0, to_port = 0, protocol = "tcp" },
    + { from_port = 1, to_port = 1, protocol = "tcp" },
    + { from_port = 2, to_port = 2, protocol = "tcp" },
  ]
```

Those port numbers (0, 1, 2) are not HTTP, HTTPS, or anything useful. The plan reveals the bug before you even look at the code.

---

### The CloudWatch alarm (Bug 4)

```hcl
resource "aws_cloudwatch_metric_alarm" "cpu" {
  count               = var.enable_monitoring ? 0 : 1
  alarm_name          = "high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 80
}
```

**What this is trying to do:** Create a CloudWatch alarm that fires when CPU utilisation on an EC2 instance exceeds 80% — but only when monitoring is switched on via the `enable_monitoring` variable.

**What CloudWatch is:** AWS CloudWatch is a monitoring service. A metric alarm watches a specific metric (here, CPU utilisation) and triggers an alert when it crosses a threshold. The settings here say: check CPU every 120 seconds, and if the average is above 80% for 2 evaluation periods in a row, the alarm fires.

**The bug:** The ternary is backwards.

```hcl
count = var.enable_monitoring ? 0 : 1
```

Read this out loud: "If monitoring is enabled, count is 0 (don't create the alarm). If monitoring is disabled, count is 1 (create the alarm)."

That's the exact opposite of the intent. The 0 and 1 need swapping.

Because `enable_monitoring` defaults to `true`, when you run `terraform plan` in this broken state, no alarm appears in the plan at all — despite monitoring being switched on. That's how you spot this bug from the plan output: you see `enable_monitoring = true` in the variables, but no CloudWatch alarm in the plan.

---

## Real-Time Learning Pathway

> **The ticket:** *"INCIDENT-TF-008: Production deployment creating resources that should only exist in staging, and missing resources that should exist in production. Conditional logic in Terraform is wrong."*
>
> You have no prior knowledge of this codebase. This is how you work through it.

---

### Step 1 — Get your bearings: what files are we working with?

```bash
ls -la
```

| Part | What it does |
|------|-------------|
| `ls` | Lists files in the current directory |
| `-la` | `-l` = long format (permissions, size, date); `-a` = include hidden files |

You'll see: `main.tf`, `variables.tf`, `CHALLENGE.md`, `HINTS.md`, `validate.sh`.

Notice what's **not** there — no `terraform.tfvars`. In most real projects you'd have a `.tfvars` file setting variable values per environment. Here, the variable defaults are declared directly inside `main.tf`. Check `variables.tf`:

```bash
cat variables.tf
```

It's empty. So all variable declarations — and their default values — live in `main.tf`. That's your starting point.

---

### Step 2 — Read main.tf and note the variable defaults

```bash
cat main.tf
```

Before running anything, scan the variable declarations at the top of `main.tf`. Note the defaults:

- `environment = "production"`
- `enable_monitoring = true`

These are the values Terraform will use since there's no `.tfvars` file overriding them. Write them down mentally — every conditional check you do later has to be evaluated against these values.

---

### Step 3 — Run a plan before touching anything

```bash
terraform init && terraform plan
```

| Command | What it does |
|---------|-------------|
| `terraform init` | Downloads the AWS provider plugin and prepares the working directory |
| `terraform plan` | Calculates what Terraform would create, change, or destroy — without doing anything |
| `&&` | Only runs the second command if the first succeeds |

The plan output is your first real source of evidence. Read it carefully before opening `main.tf` to look for bugs. Here's what you'll see and what it tells you:

**The plan shows `aws_instance.bastion[0] will be created`.**
You just noted that `environment = "production"`. A bastion host appearing in a production plan is suspicious — the ticket says something is being created that should only exist in staging. This is your first candidate bug.

**The plan shows security group ingress rules with `from_port = 0`, `from_port = 1`, `from_port = 2`.**
Those are not real application ports. Something is producing index positions instead of port numbers. Bug spotted from the plan output alone.

**The plan throws a hard error on the subnets:**
```
Error: Invalid for_each argument
  on main.tf line 32, in resource "aws_subnet" "app":
  for_each = var.subnet_cidrs
  var.subnet_cidrs is tuple with 3 elements

The given "for_each" argument value is unsuitable: the "for_each" argument
must be a map, or set of strings, and you have provided a value of type tuple.
```
Terraform can't even complete the plan. The error message tells you exactly what's wrong — `for_each` received a tuple (a list), not a set or map.

**No CloudWatch alarm appears anywhere in the plan.**
`enable_monitoring = true` — so you'd expect an alarm to be created. It's absent. The conditional must be inverted. Bug spotted by noticing what's *missing*.

The plan has surfaced all four symptoms before you've changed a single line of code.

---

### Step 4 — Fix Bug 1: bastion host in the wrong environment

The plan showed a bastion being created with `environment = "production"`. The ticket says resources are appearing that should only exist in staging. The bastion is the likely culprit.

Find it in `main.tf`:

```bash
grep -n "bastion" main.tf
```

| Part | What it does |
|------|-------------|
| `grep` | Searches for a matching pattern in a file |
| `-n` | Shows the line number of each match |
| `"bastion"` | The text pattern to search for |
| `main.tf` | The file to search in |

You'll find:

```hcl
count = var.environment == "production" ? 1 : 0
```

Read it out loud: **"If the environment is production, create 1 bastion host. Otherwise create 0."**

That's backwards. The intent — confirmed by the ticket — is staging only. Flip the condition:

```hcl
# BROKEN
count = var.environment == "production" ? 1 : 0

# FIXED
count = var.environment == "staging" ? 1 : 0
```

Read the fix out loud to verify: **"If the environment is staging, create 1 bastion host. Otherwise create 0."** Correct.

**Note:** How do you *know* a bastion shouldn't be in production if the ticket doesn't name it explicitly? The ticket says "creating resources that should only exist in staging" — it doesn't name them. You connect the dots: the plan shows a bastion, the environment is production, bastions are for direct SSH access during development and testing. Production access should go through more secure channels (SSM Session Manager or VPN). The bastion is the only EC2 instance in this config — it must be the one the ticket is referring to.

---

### Step 5 — Fix Bug 2: for_each on a list

The plan threw a hard error — `for_each` received a tuple (list) instead of a set. The plan can't complete until this is fixed.

Find the subnet resource:

```bash
grep -n "for_each" main.tf
```

You'll find:

```hcl
resource "aws_subnet" "app" {
  for_each   = var.subnet_cidrs
  vpc_id     = aws_vpc.main.id
  cidr_block = each.value
}
```

`var.subnet_cidrs` is a list. `for_each` requires a set or map. Wrap the list with `toset()`:

```hcl
# BROKEN
for_each = var.subnet_cidrs

# FIXED
for_each = toset(var.subnet_cidrs)
```

`toset()` converts the list `["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]` into a set. Each subnet is now identified in Terraform's state by its CIDR value — `aws_subnet.app["10.0.1.0/24"]` — rather than its position (`aws_subnet.app[0]`). That's stable and safe.

---

### Step 6 — Fix Bug 3: dynamic block using .key instead of .value

You saw from the plan that the security group ingress rules were created for ports 0, 1, 2. Now you know what to look for in the code.

Find the dynamic block:

```bash
grep -n "ingress.key" main.tf
```

You'll find:

```hcl
dynamic "ingress" {
  for_each = [80, 443, 8080]
  content {
    from_port = ingress.key
    to_port   = ingress.key
    ...
  }
}
```

Ask yourself: do I want the *position* of each port in the list, or the *actual port number itself*?

- `ingress.key` → position (0, 1, 2)
- `ingress.value` → actual element (80, 443, 8080)

You want the port numbers. Change both references:

```hcl
# BROKEN
from_port = ingress.key
to_port   = ingress.key

# FIXED
from_port = ingress.value
to_port   = ingress.value
```

---

### Step 7 — Fix Bug 4: CloudWatch alarm is inverted

You noticed no alarm appeared in the plan despite `enable_monitoring = true`. Find the alarm:

```bash
grep -n "enable_monitoring" main.tf
```

You'll find:

```hcl
count = var.enable_monitoring ? 0 : 1
```

Read it out loud: **"If monitoring is enabled, count is 0 — don't create the alarm. If monitoring is disabled, count is 1 — create the alarm."**

The 0 and 1 are swapped. Fix them:

```hcl
# BROKEN — creates alarm when monitoring is disabled
count = var.enable_monitoring ? 0 : 1

# FIXED — creates alarm when monitoring is enabled
count = var.enable_monitoring ? 1 : 0
```

Read the fix: **"If monitoring is enabled, count is 1 — create the alarm."** Correct.

---

### Step 8 — Validate and confirm with a clean plan

```bash
terraform validate
terraform plan
```

| Command | What it does |
|---------|-------------|
| `terraform validate` | Checks HCL syntax and types without contacting AWS. Fast. |
| `terraform plan` | Full dry-run. Shows exactly what would be created, changed, or destroyed. |

**What to verify in the clean plan:**

- No bastion host appears (environment is `production` — bastion should now be absent)
- Three subnets appear, identified by CIDR value, no type error
- Security group ingress rules show `from_port = 80`, `from_port = 443`, `from_port = 8080`
- CloudWatch alarm appears (monitoring is enabled)
- No errors

---

## Full Bug Reference

| # | Bug | How you spotted it | Root cause | Fix |
|---|-----|--------------------|------------|-----|
| 1 | Bastion in wrong environment | Plan shows bastion; environment is production | `== "production"` should be `== "staging"` | Flip the string in the condition |
| 2 | `for_each` type error | Hard error in plan output | `for_each` received a list (tuple) | Wrap with `toset()` |
| 3 | Wrong firewall ports | Plan shows ports 0, 1, 2 | `ingress.key` returns index, not value | Change `.key` to `.value` |
| 4 | Alarm missing when monitoring on | No alarm in plan despite `enable_monitoring = true` | `? 0 : 1` should be `? 1 : 0` | Swap the ternary values |

---

## Lab vs Real Life

**No `.tfvars` file in this lab:** In production Terraform setups you'd have separate variable files per environment — `dev.tfvars`, `staging.tfvars`, `prod.tfvars` — and you'd run `terraform plan -var-file=staging.tfvars` to test each one. In this lab the variable defaults are hardcoded in `main.tf` for simplicity.

**Bastion hosts in production:** Real production environments avoid bastions. AWS SSM Session Manager gives shell access to private instances without any open inbound ports or jump boxes. Bastions are considered a legacy pattern for anything beyond dev/staging.

**`for_each` vs `count` for multiple resources:** Use `count` when resources are identical and interchangeable. Use `for_each` when each resource has a distinct identity (a subnet CIDR, an IAM policy name) — you get stable state addressing and cleaner drift detection.

**Feature flags:** Variables like `enable_monitoring` are a standard pattern for toggling capabilities per environment. In a real setup you might have `enable_monitoring = false` in `dev.tfvars` and `true` in `prod.tfvars`. Same code, different behaviour.

**Testing conditionals in CI:** Tools like `checkov` and `tflint` can assert that a plan produces the expected resources. In CI/CD pipelines it's common to run `terraform plan` against multiple `.tfvars` files and check the output.

---

## Key Concepts

- **Ternary syntax:** `condition ? value_if_true : value_if_false`. Read every ternary out loud. Getting the 1 and 0 the wrong way round inverts the entire logic.
- **`count = 0` skips a resource, `count = 1` creates it.** This is the standard pattern for optional resources in Terraform.
- **`for_each` requires a set or map, not a list.** Use `toset()` to convert. This gives stable resource addressing keyed by value, not position.
- **In a dynamic block, `.value` gives the element and `.key` gives the index.** For a list of port numbers, you almost always want `.value`.
- **`terraform plan` is your primary debugging tool.** It surfaces wrong resources, missing resources, wrong configuration values, and type errors — often before you've read a line of code.
- **When the error says "tuple", it means list.** Terraform's internal terminology. Don't let it confuse you.

---

## Cleanup

After completing the lab, revert `main.tf` to its broken state so the lab can be repeated from Step 1:

```bash
git checkout main.tf
git status
```

| Command | What it does |
|---------|-------------|
| `git checkout main.tf` | Restores `main.tf` to the last committed version (the broken state) |
| `git status` | Confirms the working directory is clean — no uncommitted changes |

No `terraform destroy` needed for this lab as the plan was never applied.
