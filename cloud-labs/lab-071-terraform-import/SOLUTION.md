# Lab 071 — Terraform Import and Resource Adoption
### Solution Walkthrough

---

## Plain-English TLDR

Someone built AWS resources by hand — clicking around in the console rather than writing Terraform code. Now the team wants Terraform to manage those resources going forward. The problem is that Terraform has no idea those resources exist. If you ran `terraform apply` right now, Terraform would try to create *brand new* copies of everything instead of recognising the ones already there.

There is no state file. That's the problem. Your job is to create one.

The fix is a process called **import**. You tell Terraform: *"That VPC already in AWS? That's the one my config is describing. Start managing it."* Once Terraform knows about it, it writes the resource into its state file, and from that point on manages it like normal.

The steps are:
1. Run `setup.sh` — this creates the three AWS resources outside Terraform, simulating the ClickOps scenario
2. Find the IDs of those resources (they'll be saved to `.lab-resource-ids`)
3. Run `terraform init`
4. Run `terraform import` for each resource to register it in state
5. Run `terraform plan` to check for gaps between your config and reality
6. Adjust the config if needed until the plan shows no changes

---

## Background: What Is Terraform State?

Terraform keeps a file called `terraform.tfstate` that records every resource it knows about — what it created, what ID it has in AWS, what its current settings are. This is how Terraform knows the difference between "create this" and "update this."

When a resource was created manually (outside Terraform), the state file has no record of it. Terraform treats it as if it doesn't exist — so it would plan to create a duplicate.

**`terraform import` bridges this gap.** It reads the real resource from AWS and writes a record of it into the state file, linking it to the resource block in your `.tf` file. No infrastructure is created or destroyed. Only the state file changes.

---

## Real-Time Investigation Walkthrough

You've been handed a ticket:

> *"INCIDENT-TF-005: Team wants to manage manually-created resources with Terraform. We have a VPC, subnet, and security group that were created in the console. Running terraform apply would create duplicates. Need to import existing resources into state."*

You arrive at the lab directory. There's a `main.tf` already written, no state file, and a `setup.sh` that simulates the manual resource creation. Here's how you work through this from scratch.

---

### Step 1 — Run the Setup Script to Create the Manual Resources

**The question you're asking:** *Where are the manually-created resources the ticket is referring to?*

In a real incident, someone already clicked around in the AWS console weeks ago. In this lab, the setup script simulates that:

```bash
bash setup.sh
```

**What this does:** Uses the AWS CLI to create a VPC, subnet, and security group in your AWS account — exactly as if a human had done it via the console. No Terraform. No state file. Just raw AWS resources.

You'll see output like:

```
  ✅  VPC created: vpc-0a1b2c3d4e5f
  ✅  Subnet created: subnet-0b2c3d4e5f6a
  ✅  Security group created: sg-0c3d4e5f6a7b

  IDs saved to .lab-resource-ids
```

The IDs are saved to `.lab-resource-ids` in the lab directory so you can reference them throughout the lab.

---

### Step 2 — Orient Yourself: What Does the Config Say?

**The question you're asking:** *The ticket says there's a Terraform config already written. What does it describe?*

```bash
cat main.tf
```

You'll see three resource blocks — `aws_vpc.main`, `aws_subnet.public`, and `aws_security_group.web`. They describe resources with specific names, CIDR blocks, and tags.

**Why does this matter?** These resource blocks are your targets for import. When you run `terraform import`, the first argument is the resource address from this file (e.g. `aws_vpc.main`). You need to know the exact type and name before you can import anything.

---

### Step 3 — Confirm the Resources Exist in AWS

**The question you're asking:** *Before I start importing, can I verify the resources are actually there and see their IDs?*

The IDs are in `.lab-resource-ids`, but it's good practice to confirm with the AWS CLI — this is what you'd do in a real incident where someone hands you a resource name and says "go find it":

```bash
aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=production-vpc" \
  --query 'Vpcs[0].VpcId' \
  --output text
```

**Command breakdown:**

| Part | What it does |
|------|-------------|
| `aws ec2 describe-vpcs` | Calls the EC2 API to list VPCs in your account |
| `--filters "Name=tag:Name,Values=production-vpc"` | Narrows results to VPCs with a `Name` tag matching `production-vpc` |
| `--query 'Vpcs[0].VpcId'` | From the JSON response, extracts just the VpcId of the first match |
| `--output text` | Returns plain text rather than JSON — easier to copy |

You should get back a VPC ID like `vpc-0a1b2c3d4e5f`. If you get `None`, the filter tag doesn't match — double-check the tag value in AWS.

Do the same for the subnet and security group:

```bash
aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=public-subnet" \
  --query 'Subnets[0].SubnetId' \
  --output text

aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=web-sg" \
  --query 'SecurityGroups[0].GroupId' \
  --output text
```

**Note on the security group filter:** Security groups use `group-name` — a first-class attribute — rather than a tag filter. This is how the AWS CLI distinguishes between filtering on a tag vs filtering on a native resource property.

---

### Step 4 — Initialise Terraform

**The question you're asking:** *Can I run Terraform commands yet?*

```bash
terraform init
```

**Command breakdown:**

| Part | What it does |
|------|-------------|
| `terraform init` | Downloads the AWS provider plugin, sets up the `.terraform` directory, prepares the backend. Must be run before any other Terraform command in a fresh directory. |

You're looking for: `Terraform has been successfully initialized!`

Now run plan to see what Terraform currently thinks it needs to do:

```bash
terraform plan
```

**What you'll see:** Terraform plans to *create* all three resources. It has no state, so it assumes nothing exists yet.

**This is exactly the problem.** If you ran `terraform apply` now, it would try to create duplicates of resources that already exist in AWS. This is why you import first.

---

### Step 5 — Import Each Resource

**The question you're asking:** *How do I tell Terraform "that existing AWS resource — that's the one my config is describing"?*

This is the core of the lab. You run one `terraform import` command per resource. The syntax is:

```
terraform import <resource-address> <aws-resource-id>
```

Start with the VPC:

```bash
terraform import aws_vpc.main <your-vpc-id>
```

**Command breakdown:**

| Part | What it does |
|------|-------------|
| `terraform import` | Updates state only — no infrastructure is created or changed |
| `aws_vpc.main` | The resource address: type `aws_vpc`, name `main` — must exactly match the block in `main.tf` |
| `<your-vpc-id>` | The actual AWS resource ID from Step 3 (e.g. `vpc-0a1b2c3d4e5f`) |

You should see: `Import successful!`

Now import the subnet:

```bash
terraform import aws_subnet.public <your-subnet-id>
```

And the security group:

```bash
terraform import aws_security_group.web <your-sg-id>
```

**How do you know what ID format to use for each resource type?**

Different resource types use different ID formats:
- VPCs → `vpc-xxx`
- Subnets → `subnet-xxx`
- Security groups → `sg-xxx`
- S3 buckets → the bucket *name* (not an ARN)
- IAM roles → the role *name*

The rule: check the [Terraform AWS provider docs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs) for each resource. Every page has an "Import" section at the bottom that tells you exactly what format to use.

After all three imports, verify the state:

```bash
terraform state list
```

**Command breakdown:**

| Part | What it does |
|------|-------------|
| `terraform state list` | Lists every resource currently recorded in the state file |

You should see:
```
aws_security_group.web
aws_subnet.public
aws_vpc.main
```

If a resource is missing, the import didn't succeed for that one — re-run the import command for it.

---

### Step 6 — Check for Drift

**The question you're asking:** *Now that Terraform knows about these resources, does my config actually match what's in AWS?*

```bash
terraform plan
```

**What you're hoping to see:** `No changes. Your infrastructure matches the configuration.`

**What it means if you see changes:** Your `main.tf` config doesn't perfectly match the real resource attributes. For example, the real VPC might have `enable_dns_support = true` but your config doesn't mention it, so Terraform sees a difference.

Read the plan output carefully. For each difference, decide:
- Is the real AWS setting correct? → Update `main.tf` to match it
- Do you want Terraform to change it? → Leave the config and let apply handle it

If you update the config, run `terraform plan` again to confirm the drift is resolved.

---

### Step 7 — Validate

```bash
bash validate.sh
```

The validator checks:
- Terraform config is syntactically valid
- A state file exists (import has actually been run)
- All three resources appear in state
- `terraform plan` completes without errors
- `terraform plan` shows no pending changes (config matches reality)

You need all checks green before this lab is complete.

---

## Lab vs Real Life

**In this lab:** The setup script creates the resources and hands you the IDs. The config is already written. You focus purely on the import mechanics.

**In real life, this is messier:**

- You have to *write* the Terraform config yourself — reverse-engineering what someone clicked in the console. In Terraform 1.5+, `terraform plan -generate-config-out=generated.tf` can draft a starting point from an imported resource.
- You often don't know all the resource IDs upfront and have to hunt for them using tags, names, and `describe-*` CLI commands.
- Large environments may have dozens of manually-created resources. Tools like `terraformer` and `aws2tf` can bulk-import them.
- Some resources have sub-resources that need separate imports. Importing an `aws_security_group` doesn't automatically import standalone `aws_security_group_rule` resources if they're defined separately.
- **Always back up state before importing in production:**
  ```bash
  cp terraform.tfstate terraform.tfstate.backup
  ```
- Modern GitOps teams use `import` blocks in `.tf` files rather than CLI commands — this makes the import version-controlled and repeatable:
  ```hcl
  import {
    to = aws_vpc.main
    id = "vpc-0a1b2c3d4e5f"
  }
  ```

---

## Cleanup / Reset

### Happy path — lab completed successfully

Once the imports are done and the plan is clean, Terraform owns the resources. Use Terraform to destroy them:

```bash
terraform destroy
```

This is the correct approach when the lab has been completed properly. Terraform knows about the resources, so let it clean them up. It also handles deletion order automatically — security group before subnet before VPC.

### Bail-out path — abandoned mid-lab or state is broken

If you exit the lab before completing the imports, Terraform can't destroy what it doesn't know about. Use the teardown script instead:

```bash
bash teardown.sh
```

This uses the AWS CLI directly to delete the resources and wipe the state file, regardless of what Terraform does or doesn't know. It's the reset button.

After either path, run `setup.sh` to start from scratch.

---

## Common Mistakes

**Drift on security group description** — if `main.tf` doesn't specify a `description` on `aws_security_group`, Terraform defaults to `"Managed by Terraform"`. If the real resource has a different description (e.g. `"Web security group"`), the plan will show a replacement — not just an update — because `description` is immutable on a security group. Always explicitly set `description` in your config to match what was created manually.

**Running `terraform apply` before importing** — Terraform plans to create duplicates. Import first. Run `terraform plan` after init to see the problem, then import to fix it.

**Getting the resource address wrong** — `terraform import aws_vpc.main vpc-xxx` only works if `main.tf` has `resource "aws_vpc" "main" { ... }`. Both the type and name must match exactly.

**Using the wrong ID format** — Each resource type has its own import ID format. Check the Terraform provider docs "Import" section for each resource.

**Not checking for drift after import** — Import succeeds even if your config doesn't match reality. Always run `terraform plan` afterwards. A mismatched config will cause Terraform to modify or recreate the resource on the next apply.

**Importing partial dependencies** — If you import the subnet but not the VPC, Terraform will plan to create a new VPC. Import all related resources together, in dependency order: VPC first, then subnet, then security group.
