# Lab 061 — Terraform State Mismatch (Drift Detection)

---

## TLDR — Plain English Summary

Terraform keeps a record of everything it has built in AWS — a file called the state file. Think of it like a spreadsheet that tracks every resource: what it's called, what settings it has, what its ID is in AWS.

When someone goes into the AWS console and makes changes directly — bypassing Terraform — that spreadsheet becomes out of date. Terraform still thinks the world looks one way, but reality has moved on. This gap is called **drift**.

In this lab, three things were changed in the console after the initial apply:

1. **S3 bucket tags were changed** from `staging/ops` to `production/engineering` — an intentional correction
2. **Bucket versioning was switched on** — also intentional, good practice for production
3. **The security group was deleted** — a mistake

`terraform plan` detects all three. The job is to decide what to do about each one — update the config to accept the console changes, or let Terraform revert them — then apply to bring everything back into alignment.

---

## Key Concept: What Is State Drift?

Terraform manages infrastructure through three things that should always match:

- **Configuration (`main.tf`)** — what you want to exist
- **State file (`terraform.tfstate`)** — what Terraform thinks currently exists
- **AWS reality** — what actually exists

When someone changes AWS directly (console, CLI, another tool), reality moves without the state file or config knowing. `terraform plan` compares all three and shows you the differences. That's drift detection.

**Important:** `terraform plan` tells you *what* drifted. It cannot tell you *why* or *whether it was intentional*. That always requires human context — CloudTrail logs, team communication, or change management records.

---

## Understanding the Plan Output

When you run `terraform plan` after the corruption script, you see three things:

### Reading the symbols

| Symbol | Meaning |
|--------|---------|
| `+` | Resource will be created — doesn't exist yet |
| `-` | Resource will be destroyed |
| `~` | Resource will be updated in-place |
| `-/+` | Resource will be destroyed and recreated |

### Reading the arrow direction

```
~ "Environment" = "production" -> "staging"
```

Left of the arrow = **current AWS reality**
Right of the arrow = **what your config says it should be**

So this line means: AWS currently has `production`, your config says `staging`, Terraform is planning to change it to `staging`. In this case that's wrong — the config is stale and needs updating.

---

## Diagnostic Pathway

### Phase 1: Read the plan before touching anything

```bash
terraform plan
```

| Part | What it does |
|------|-------------|
| `terraform` | The Terraform CLI |
| `plan` | Compares config + state + AWS reality, shows proposed changes without making them |

Read every section. For each proposed change ask: *is this Terraform trying to fix something, or trying to undo something correct?*

---

### Scenario 1: Tag Drift

**What the plan shows:**
```
~ tags = {
    ~ "Environment" = "production" -> "staging"
    ~ "Team"        = "engineering" -> "ops"
  }
```

**Investigative questions:**

1. *Which direction is the drift?* AWS has `production/engineering`. Config says `staging/ops`. Terraform wants to revert to staging.

2. *Was the console change intentional?* Yes — someone correctly retagged the bucket for production use.

3. *So what needs changing?* The config is wrong, not AWS. Update `main.tf` to declare the correct tags.

4. *Where do I make the change?* The `aws_s3_bucket` resource block in `main.tf`, inside the `tags` block.

**The fix:**

```hcl
resource "aws_s3_bucket" "data" {
  bucket = "company-data-${random_id.suffix.hex}"
  tags = {
    Environment = "production"
    Team        = "engineering"
  }
}
```

After this change, config matches AWS reality. On the next plan, Terraform sees no difference and proposes no change.

---

### Scenario 2: Versioning Drift

**What the plan shows:**
```
Error: versioning_configuration.status cannot be updated 
from 'Enabled' to 'Disabled'
```

**Investigative questions:**

1. *Why is this an error rather than a planned change?* AWS enforces a one-way rule on S3 versioning — once enabled, it cannot be fully disabled. You can only suspend it. Terraform tried to plan `Enabled → Disabled` and AWS rejected it.

2. *Was the console change intentional?* Yes — versioning on a production bucket is correct practice. It protects against accidental deletions.

3. *What needs changing?* The config needs to accept the new reality. Change `"Disabled"` to `"Enabled"`.

4. *What's the real-world lesson?* Some console changes are irreversible. You can't just "let Terraform revert it." The config must be updated to match.

**The fix:**

```hcl
resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id
  versioning_configuration {
    status = "Enabled"
  }
}
```

---

### Scenario 3: Deleted Security Group

**What the plan shows:**
```
# aws_security_group.app will be created
+ resource "aws_security_group" "app" {
```

**Investigative questions:**

1. *Why is Terraform planning to create it rather than erroring?* The AWS provider detected the SG is gone during the refresh phase and updated its understanding accordingly. It knows the resource no longer exists, so rather than trying to manage a dead ID it plans to create a fresh one.

2. *Was the console change intentional?* No — the security group being silently deleted with no change request is almost certainly a mistake.

3. *Do I need to change `main.tf`?* No. The SG definition stays in `main.tf` exactly as it is. That's the blueprint saying "this should exist." Terraform will recreate it on apply.

4. *Do I need to run `terraform state rm`?* In this case, no — the AWS provider handled it gracefully. However, in older provider versions or different resource types, Terraform can error out hard when trying to refresh a deleted resource. In those cases `terraform state rm` clears the stale entry so Terraform can get past the error.

**`terraform state rm` explained:**

```bash
terraform state rm aws_security_group.app
```

| Part | What it does |
|------|-------------|
| `terraform` | The Terraform CLI |
| `state` | Sub-command for directly manipulating the state file |
| `rm` | Removes a resource record from the state file |
| `aws_security_group.app` | The resource address — type and name matching the `main.tf` block |

**Critical point:** `state rm` does NOT delete anything in AWS. It only removes Terraform's memory of the resource. The blueprint (`main.tf`) still says it should exist, so the next apply creates a new one.

**No fix needed in `main.tf` for this scenario.** Terraform handles it automatically.

---

### Phase 2: Apply the fixes

After updating the two config values, run:

```bash
terraform plan
```

Expected output:
- Tags: no change proposed — config now matches AWS
- Versioning: no error — config now says `Enabled`, AWS is `Enabled`
- Security group: `+ create` — Terraform will recreate the deleted one

Then:

```bash
terraform apply
```

| Part | What it does |
|------|-------------|
| `terraform` | The Terraform CLI |
| `apply` | Executes the planned changes in AWS |

Type `yes` to confirm. After apply: tags are correct, versioning is enabled, security group is recreated, state matches config matches AWS reality.

---

### Phase 3: Verify

```bash
terraform plan
```

A clean result:
```
No changes. Your infrastructure matches the configuration.
```

This confirms drift is fully resolved.

```bash
./validate.sh
```

| Part | What it does |
|------|-------------|
| `./` | Run from current directory |
| `validate.sh` | Lab script that runs `terraform validate` and `terraform plan` to confirm everything is valid |

---

### Phase 4: Destroy and clean up

```bash
terraform destroy
```

| Part | What it does |
|------|-------------|
| `terraform` | The Terraform CLI |
| `destroy` | Removes all resources managed by this configuration from AWS |

Type `yes` to confirm. **Always destroy lab resources when finished — AWS charges for running resources.**

Then clean up local Terraform files ready for a fresh run:

```bash
rm -f terraform.tfstate terraform.tfstate.backup
rm -rf .terraform
rm -f .terraform.lock.hcl
```

---

## Understanding the Terraform Files

These files appear in your lab directory during and after a Terraform workflow. Here's what each one is and why it matters:

### `terraform.tfstate`

Terraform's record of everything it manages. Written after every `apply` or `destroy`. Contains resource IDs, attributes, and metadata for every resource Terraform created.

**Why you delete it for a fresh lab run:** Without deleting it, the next `terraform init` + `apply` would think the resources already exist. You'd get drift from the start.

**Why it's in `.gitignore`:** State files contain sensitive data (resource IDs, sometimes secrets). They also cause merge conflicts in team environments. In production, state is stored remotely — S3 + DynamoDB or Terraform Cloud — never in a git repo.

### `terraform.tfstate.backup`

A copy of the previous state file, written automatically before every operation that modifies state. If something goes wrong during an apply, this is your recovery point.

**Why you delete it for a fresh lab run:** Same reason as the state file — stale data that would confuse a fresh run.

### `.terraform/`

A directory created by `terraform init`. Contains the downloaded provider plugins (the AWS provider, the random provider, etc.) and internal Terraform metadata.

**Why you delete it for a fresh lab run:** Forces a clean `terraform init` next time, ensuring the latest provider versions are downloaded. Safe to delete — it's always regenerated by `init`.

### `.terraform.lock.hcl`

A lock file created by `terraform init`. Records the exact versions of providers that were selected, so every subsequent `init` uses the same versions. Similar in concept to `package-lock.json` in Node or `Gemfile.lock` in Ruby.

**Why you delete it for a fresh lab run:** Allows the next `init` to resolve provider versions fresh. In a real project you'd commit this to git — it ensures everyone on the team uses identical provider versions.

---

## Key Commands Reference

| Command | When to use it |
|---------|---------------|
| `terraform init` | First thing, every time — downloads providers, sets up backend |
| `terraform plan` | Your diagnostic tool — shows what Terraform intends to change |
| `terraform apply` | Executes the plan — makes real changes in AWS |
| `terraform destroy` | Tears everything down — always run at end of lab |
| `terraform state rm <address>` | Removes a stale resource record from state without touching AWS |
| `terraform state list` | Lists all resources currently tracked in state |
| `terraform state show <address>` | Shows full details of a specific resource in state |
| `terraform apply -refresh-only` | Updates state to match current AWS reality without changing infrastructure |

---

## Resource Addresses

When using `terraform state rm`, `terraform state show`, or `terraform import`, you need the resource address. Format is always:

```
<resource_type>.<resource_name>
```

This maps directly to the resource block in `main.tf`:

```hcl
resource "aws_security_group" "app" {   # → aws_security_group.app
resource "aws_s3_bucket" "data" {       # → aws_s3_bucket.data
```

---

## Real World vs Lab

| Topic | Lab | Production |
|-------|-----|------------|
| State storage | Local `terraform.tfstate` | Remote — S3 + DynamoDB or Terraform Cloud |
| State locking | Not needed (solo) | DynamoDB prevents two engineers applying simultaneously |
| Drift detection | Manual — run `terraform plan` | Automated — CI/CD runs plan on a schedule, alerts on drift |
| Who made console changes | The corruption script | CloudTrail logs, change management records, team communication |
| Versioning once enabled | Cannot disable — only suspend | Same AWS constraint applies everywhere |
| State in git | Never — sensitive data, merge conflicts | Never — always use remote state backend |

---

## Common Mistakes

**Reading the arrow direction wrong**
`"production" -> "staging"` means AWS has `production` and Terraform wants to change it to `staging`. Left is current reality, right is where the config wants to take it.

**Thinking `state rm` deletes the AWS resource**
It only removes Terraform's tracking record. The resource in AWS is unaffected (or already gone). The config still defines it, so apply will recreate it.

**Thinking you need to remove the SG from `main.tf`**
No. The blueprint stays. You want the SG to exist — you just need Terraform to create a fresh one because the old one was deleted.

**Committing `terraform.tfstate` to git**
State files contain sensitive resource metadata and cause merge conflicts. Always add to `.gitignore` and use remote state in production.

**Not reading the plan before applying**
`terraform apply` will execute exactly what `plan` showed. If plan shows Terraform reverting intentional changes, applying will make it happen. Always read the plan.

**Forgetting to destroy lab resources**
AWS charges for running resources even when you're not using them. Always `terraform destroy` at the end of a lab.
