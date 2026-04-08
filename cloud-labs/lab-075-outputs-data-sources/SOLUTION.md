# Lab 075 — Outputs and Data Sources

## Plain-English TLDR

You've been handed a Terraform config that's broken in three ways. First, it's trying to launch an EC2 instance using a hardcoded AMI ID that doesn't exist — AMI IDs are region-specific and go stale, so you should never hardcode them. Second, the config doesn't expose any of its values (like the VPC ID or instance IP) to the outside world via outputs — meaning any other module or pipeline that tries to reference them will fail. Third, there's an output that says it's a public IP but actually returns a private IP — a naming mismatch that Terraform won't catch for you, but that causes real confusion downstream.

One important thing to know before you start: **Bug 1 won't surface during `terraform plan` — only during `terraform apply`**. Terraform doesn't validate AMI IDs against AWS at plan time. It just trusts you. The failure only lands when AWS actually tries to launch the instance and rejects the ID. And **Bug 3 will never be caught by Terraform at all** — it's a naming problem, not a syntax problem, and it's invisible to the tool entirely.

---

## Background: What Are Outputs and Data Sources?

### Data Sources

A **data source** lets Terraform read existing information from AWS without creating anything. Think of it like a query. Instead of hardcoding an AMI ID (which will break when the AMI is updated or you switch regions), you ask AWS: *"What's the latest Ubuntu 22.04 AMI right now?"* Terraform fetches the answer at plan time and uses it.

**Why this matters:** AMI IDs are region-specific. `ami-0abc123` in `us-east-1` is a completely different image in `eu-west-2` — or doesn't exist at all. And Canonical (the company that makes Ubuntu) publishes updated AMIs regularly — the same ID from six months ago now points to an image with unpatched security vulnerabilities. Teams that hardcode AMI IDs spend time debugging mysterious launch failures when AMIs are deprecated.

### Outputs

**Outputs** are how a Terraform module exposes values to the outside world. When your config is used as a module by another team (or by your CI/CD pipeline), outputs are the only way they can access values like a VPC ID or an instance's private IP. Without outputs, those values are trapped inside the module — referencing `module.network.vpc_id` would fail with an unknown value error.

### outputs.tf vs main.tf

Terraform doesn't care which file your outputs live in — it reads all `.tf` files in the directory. But the convention is to keep them separate:

| File | What goes in it |
|---|---|
| `main.tf` | Resources and data sources |
| `variables.tf` | Input variables |
| `outputs.tf` | Output values |
| `providers.tf` | Provider configuration |

When another engineer picks up your module, they know exactly where to look. If they want to know what values this module exposes, they open `outputs.tf` — they don't have to scan through hundreds of lines of resource definitions. It's the same principle as a clean public API: the interface is documented in one predictable place.

---

## Real-Time Investigative Walkthrough

You've just received a ticket:

> *"Terraform config in `cloud-labs/lab-075-outputs-data-sources` is broken. Instance won't launch. Other modules also can't reference VPC or subnet values. Please investigate and fix."*

That's all you know. Let's work through it.

---

### Step 1 — Get Oriented: What Does This Config Actually Do?

Before touching anything, read the config. Your first question as an engineer is always: *what is this thing trying to build?*

```bash
cat main.tf
```

| Component | What it does |
|---|---|
| `cat` | Prints the contents of a file to your terminal |
| `main.tf` | The main Terraform configuration file for this lab |

Read through it. You're looking for:
- What resources are being created?
- Are there any `data` blocks?
- Are there any `output` blocks?

**What you'll notice:**
- There's an `aws_instance` resource
- The `ami` field has a hardcoded value: `"ami-0123456789abcdef0"`
- There are no `data` blocks anywhere
- There are no `output` blocks anywhere

Make a mental note of all three. You haven't diagnosed anything yet — just observed.

---

### Step 2 — Run a Plan and Read the Output

Now try actually running Terraform. Don't guess — gather evidence.

```bash
terraform init
terraform plan
```

| Command | What it does |
|---|---|
| `terraform init` | Downloads providers and sets up the working directory |
| `terraform plan` | Shows what Terraform *would* do — doesn't create anything yet |

**What you'll see — and what you won't:**

The plan will complete without errors. Terraform will say it's going to create three resources: a VPC, a subnet, and an EC2 instance with `ami = "ami-0123456789abcdef0"`. No warnings, no errors.

This is important: **Terraform does not validate AMI IDs against AWS during plan.** It only checks that the HCL is syntactically correct and that references between resources are valid. Whether that AMI actually exists in your region is something Terraform doesn't know yet — it trusts you.

You will also see at the bottom:

```
Changes to Outputs:
  + app_public_ip = (known after apply)
```

That output is already visible in the plan — and if you look carefully, you can already spot the naming problem (Bug 3) before you've even applied. But Terraform raises no warning about it.

**What the plan does NOT tell you:**
- That the AMI ID is fake
- That you're missing outputs for VPC ID, subnet ID, instance ID, and private IP
- That `app_public_ip` is a misleading name

All of that you have to catch yourself.

---

### Step 3 — Apply and Observe the Failure

```bash
terraform apply
```

| Command | What it does |
|---|---|
| `terraform apply` | Creates the resources — prompts for confirmation first |

**What actually happens:**

Terraform creates the VPC and subnet successfully — then fails when it tries to launch the instance:

```
Error: creating EC2 Instance: operation error EC2: RunInstances,
api error InvalidAMIID.Malformed: Invalid id: "ami-0123456789abcdef0"
```

Two things to notice here:

1. **The error is `InvalidAMIID.Malformed`** — not `NotFound`. AWS is rejecting the ID format itself before even checking whether it exists. The suspiciously round number `ami-0123456789abcdef0` doesn't match AWS's expected format — a strong signal it was invented as a placeholder.

2. **The VPC and subnet were created successfully** — Terraform works through resources in dependency order. The VPC and subnet have no dependency on the AMI, so they got built first. Now you have resources sitting in AWS even though the apply "failed." This is **partial state** — those resources are in your state file and will need to be worked with on the next apply.

---

### Step 4 — Diagnose Bug 1: The Hardcoded AMI

You've confirmed the AMI ID is fake. Now ask: *how should this actually be done?*

AMI IDs are:
- **Region-specific** — an ID that works in `us-east-1` doesn't exist in `eu-west-2`
- **Time-limited** — Canonical publishes updated Ubuntu AMIs regularly; old ones get deprecated
- **Never safe to hardcode** — the correct approach is a data source that queries AWS for the right AMI at plan time

**First: discover what AMIs actually exist in your region**

Before writing the data source, verify what you're working with. Run this to query AWS directly:

```bash
aws ec2 describe-images \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
  --query "Images[*].[ImageId,Name,CreationDate]" \
  --output table \
  | head -20
```

| Component | What it does |
|---|---|
| `aws ec2 describe-images` | Lists AMIs available in your current AWS region |
| `--owners 099720109477` | Filters to only Canonical's official AMIs — see note below |
| `--filters "Name=name,Values=..."` | Narrows results to AMIs whose name matches the Ubuntu 22.04 pattern |
| `--query "Images[*].[ImageId,Name,CreationDate]"` | Selects only ID, name, and creation date from the results |
| `--output table` | Formats the output as a readable table |
| `\| head -20` | Limits terminal output to 20 lines |

**What you'll see** — multiple AMI IDs, all for Ubuntu 22.04, with different date stamps:

```
| ami-0ec2a5ff1be0688fa | ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-20260320 | 2026-03-20 |
| ami-0eb87a5de1d2bc177 | ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-20260317 | 2026-03-18 |
| ami-0be2988e4d5a5c301 | ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-20251122 | 2025-11-22 |
```

This proves the point: multiple different AMI IDs, all Ubuntu 22.04, all valid — and all different. If you'd hardcoded the November 2025 ID, you'd now be pinned to an image with months of unpatched vulnerabilities.

This output also shows you the **name pattern** to use in your filter. All names follow `ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-XXXXXXXX` where the last part is a date stamp. The `*` wildcard catches all of them, and `most_recent = true` picks the newest.

> **"How would I know to use owner `099720109477`?"**
> This is Canonical's AWS account ID — the company that publishes Ubuntu. They document it publicly. In practice you'd find it one of three ways: (1) AWS or Canonical's documentation, (2) your organisation's runbook, or (3) find a trusted Ubuntu AMI in the AWS Console, click it, and read the Owner field. Without specifying an owner you're searching millions of public AMIs from unknown sources — a real security risk.

> **"How would I know to filter for `jammy-22.04`?"**
> "Jammy" is Ubuntu's codename for version 22.04 (Jammy Jellyfish). In real life the version would be specified in the ticket or your team's OS standard. If you're making the call yourself, you'd pick an LTS (Long Term Support) release — 22.04 gets 5 years of security patches. If you weren't sure of the exact name pattern, you'd run the command above with a loose wildcard like `ubuntu*22.04*` first, see what names come back, and tighten the filter from there.

**Fix for Bug 1 — replace the hardcoded AMI with a data source in `main.tf`:**

```hcl
# Add this data block
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]   # Canonical — official Ubuntu publisher

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# Update the instance to reference the data source
resource "aws_instance" "app" {
  ami           = data.aws_ami.ubuntu.id   # Dynamic — always finds the latest AMI
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.app.id

  tags = {
    Name = "app-server"
  }
}
```

**Data source attribute breakdown:**

| Attribute | What it does |
|---|---|
| `most_recent = true` | If multiple AMIs match the filter, picks the newest one |
| `owners = ["099720109477"]` | Only return AMIs owned by Canonical's AWS account |
| `filter { name = "name" ... }` | Matches AMIs whose name fits the Ubuntu 22.04 naming pattern |
| `data.aws_ami.ubuntu.id` | Reference syntax — reads the `id` attribute from the data source result |

> **Reference syntax:** `data.<type>.<name>.<attribute>` is how you reference any data source in Terraform. Here: type is `aws_ami`, name is `ubuntu` (what we called it), attribute is `id`.

---

### Step 5 — Diagnose Bug 2: Missing Outputs

Now think about the second part of the ticket: *"Other modules can't reference VPC or subnet values."*

You've already noticed there are no output blocks in the config. Confirm this:

```bash
terraform output
```

| Command | What it does |
|---|---|
| `terraform output` | Lists all values declared as outputs in the current state |

After a successful apply with no outputs defined, this returns nothing useful. A CI/CD pipeline calling `terraform output vpc_id` would get nothing back. Another module referencing `module.app.vpc_id` would fail with an unknown value error.

**Fix for Bug 2 — create a separate `outputs.tf` file:**

Rather than adding outputs to `main.tf`, create `outputs.tf`. This is the Terraform convention — it keeps your module's public interface in one predictable place.

```hcl
# outputs.tf

output "vpc_id" {
  value       = aws_vpc.main.id
  description = "The ID of the VPC"
}

output "subnet_id" {
  value       = aws_subnet.app.id
  description = "The ID of the application subnet"
}

output "instance_id" {
  value       = aws_instance.app.id
  description = "The ID of the application EC2 instance"
}

output "instance_private_ip" {
  value       = aws_instance.app.private_ip
  description = "The private IP address of the app server"
}
```

**Output block breakdown:**

| Attribute | What it does |
|---|---|
| `value` | The Terraform expression whose result will be exported |
| `description` | Human-readable explanation — documents what each output contains |
| `aws_vpc.main.id` | Reads the `id` attribute of the VPC resource named `main` |
| `aws_instance.app.private_ip` | Reads the private IP assigned to the instance after launch |

> **Why a separate file?** Terraform reads all `.tf` files in the directory — file names don't matter to the tool. But convention is `main.tf` for resources, `outputs.tf` for outputs, `variables.tf` for inputs, `providers.tf` for providers. When another engineer opens your module, they know exactly where to look without reading everything.

---

### Step 6 — Diagnose Bug 3: The Misleading Output

Now look at the output that already exists in the config. Read it carefully:

```hcl
output "app_public_ip" {
  value       = aws_instance.app.private_ip
  description = "The public IP of the app server"
}
```

The name says `public_ip`. The description says "The public IP." But the value is `private_ip`.

**Will `terraform plan` or `terraform apply` catch this?** No. Never. Terraform validates structure — that the output has a name, a value referencing a real attribute, and a string description. Whether the name and description accurately describe the value is something Terraform has no way to know. This bug is completely invisible to the tool.

**When does it actually cause a problem?**

Only when a human or downstream system tries to use it:
- Another engineer writes `module.app.app_public_ip`, passes the result to a load balancer, and wonders why traffic isn't routing — because it's a private IP
- A script tries to SSH to the returned IP from outside and gets a timeout
- Someone reads `terraform output app_public_ip` and makes a wrong assumption about the network topology

The bug can sit silently for weeks. And worth noting: this instance has no public IP anyway — there's no `associate_public_ip_address = true` and it's in a private subnet. `aws_instance.app.public_ip` would return an empty string. The output was always going to return the wrong thing regardless.

**Fix for Bug 3 — correct the name and description, move it to `outputs.tf`:**

Remove the broken output from `main.tf` and add the corrected version to `outputs.tf`:

```hcl
# REMOVE from main.tf
output "app_public_ip" {
  value       = aws_instance.app.private_ip
  description = "The public IP of the app server"
}

# ADD to outputs.tf — name, description, and value all match
output "app_private_ip" {
  value       = aws_instance.app.private_ip
  description = "The private IP address of the app server"
}
```

---

### Step 7 — Apply and Verify

```bash
terraform apply
terraform output
```

After apply, `terraform output` should return all five values with real data:

```
app_private_ip      = "10.0.1.x"
instance_id         = "i-0abc123..."
instance_private_ip = "10.0.1.x"
subnet_id           = "subnet-019732e8..."
vpc_id              = "vpc-031a09a2..."
```

Since the VPC and subnet already exist in state from the partial apply, Terraform won't recreate them — it'll just launch the instance with the corrected AMI.

---

## What Terraform Can and Cannot Catch

This lab demonstrates an important pattern worth remembering:

| Bug | Caught by `plan`? | Caught by `apply`? | Caught by Terraform at all? |
|---|---|---|---|
| Fake AMI ID | ❌ No | ✅ Yes — AWS rejects it | ✅ Eventually |
| Missing outputs | ❌ No | ❌ No | ❌ Never — you have to notice |
| Misleading output name | ❌ No | ❌ No | ❌ Never — naming is invisible to the tool |

Terraform validates **structure**, not **intent**. Naming bugs, logical mismatches, and wrong descriptions are your responsibility — caught through code review, documentation, and downstream testing.

---

## Lab vs Real Life

**AMI data sources in CI/CD:** Production pipelines use data sources to automatically pick up the latest hardened AMI from the team's internal AMI pipeline. This ensures instances always have the latest security patches without manual ID updates.

**SSM Parameter Store for AMIs:** Some teams publish their latest approved AMI ID to SSM Parameter Store and reference it with `data "aws_ssm_parameter"`. This gives a centralised place to update the AMI once, and all configs pick it up on next plan.

**Sensitive outputs:** Terraform supports `sensitive = true` to prevent values appearing in CLI output and logs:
```hcl
output "db_password" {
  value     = aws_db_instance.main.password
  sensitive = true
}
```

**Remote state data source:** To read outputs from a *different* Terraform state (e.g. a networking team's state):
```hcl
data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = "my-state-bucket"
    key    = "network/terraform.tfstate"
    region = "eu-west-2"
  }
}

subnet_id = data.terraform_remote_state.network.outputs.subnet_id
```

**Partial state is real:** When an apply fails partway through (as happened in this lab), the resources that *did* create are in your state file. Terraform will manage them on the next apply. Always check `terraform state list` after a failed apply to understand what exists before running again.

---

## Cleanup and Reset

Always destroy before resetting — if you reset the files first, Terraform loses track of what's running in AWS.

**Step 1 — destroy all AWS resources:**

```bash
terraform destroy
```

| Command | What it does |
|---|---|
| `terraform destroy` | Tears down all resources created by this config — prompts for confirmation |

**Step 2 — reset the repo to broken starting state:**

```bash
# Delete outputs.tf entirely — missing outputs is the bug, the file shouldn't exist
rm outputs.tf

# Revert main.tf to the broken state — fake AMI and misleading output restored
git checkout main.tf

# Verify you're back to broken state
cat main.tf

# Commit and push
git add .
git commit -m "reset lab-075 to broken state"
git push
```

| Command | What it does |
|---|---|
| `rm outputs.tf` | Deletes the file entirely — it shouldn't exist in the broken starting state |
| `git checkout main.tf` | Restores `main.tf` to its last committed state — the broken version with the hardcoded AMI |
| `git add .` | Stages the deletion of `outputs.tf` |
| `git commit -m "..."` | Commits the reset |
| `git push` | Pushes to remote so the lab can be repeated cleanly from any machine |

The repo should end up exactly as it started: `main.tf` with the hardcoded AMI and misleading output, and no `outputs.tf` in sight.

---

## Key Concepts Summary

- **Never hardcode AMI IDs** — use `data "aws_ami"` to dynamically find the correct AMI. Hardcoded IDs are region-specific and go stale.
- **Outputs are a module's public interface** — any value another module or pipeline needs must be an output. No output = inaccessible value.
- **Use `outputs.tf`** — Terraform doesn't require it, but convention keeps your module's interface in one predictable place.
- **Data sources read, resources create** — data sources query existing infrastructure and return attributes. They don't create or change anything.
- **Plan doesn't validate everything** — AMI IDs and other string values aren't checked against AWS at plan time. Some bugs only surface on apply.
- **Terraform can't catch naming bugs** — output names, descriptions, and values that don't match are invisible to the tool. Code review is the only defence.
- **Always specify `owners` on AMI data sources** — without it, you're searching millions of public AMIs from unknown sources.
- **Partial state happens** — a failed apply can leave some resources created. Check `terraform state list` before your next apply.
