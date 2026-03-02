# Solution Walkthrough — Terraform State Mismatch (Drift Detection)

## The Problem

Someone made manual changes to AWS resources through the console, causing **Terraform state drift**. Terraform's state file no longer matches the real infrastructure, and `terraform plan` shows unexpected changes. There are three drift scenarios:

1. **S3 bucket tags were modified in the console** — someone added or changed tags manually. Terraform wants to revert them because its state says the tags should be something else.
2. **Bucket versioning was enabled in the console but Terraform says Disabled** — someone enabled versioning manually, but the Terraform configuration still says `status = "Disabled"`. Terraform wants to disable versioning to match the config.
3. **A security group was deleted manually** — someone deleted the security group through the console, but Terraform's state still thinks it exists. Terraform will error when trying to manage a resource that no longer exists.

The goal is to reconcile Terraform's configuration and state with the intended reality.

## Thought Process

When Terraform state drifts from reality, an experienced engineer:

1. **Run `terraform plan`** — this shows exactly what Terraform thinks needs to change. Read each change carefully: is it drift to fix, or is the manual change intentional?
2. **Decide on the source of truth** — for each difference, decide: should reality match Terraform (revert the manual change), or should Terraform match reality (update the config)?
3. **Handle deleted resources** — if a resource was deleted manually but exists in state, use `terraform state rm` to remove it from state, then decide whether to recreate it.
4. **Refresh state** — `terraform refresh` (or `terraform apply -refresh-only`) updates the state file to match current reality. This is useful when manual changes should be kept.
5. **Update configuration** — after deciding what the infrastructure should look like, update `main.tf` to match.

## Step-by-Step Solution

### Step 1: Initialize and check the current plan

```bash
terraform init
terraform plan
```

**What this does:** Shows what Terraform thinks needs to change. You'll see three types of issues:
- Tag changes it wants to revert
- Versioning it wants to disable
- An error about a resource that no longer exists (the deleted security group)

### Step 2: Fix Bug 1 — Update the S3 bucket tags

The tags in `main.tf` should reflect the desired state. If the console changes were intentional (which they are in this scenario — someone correctly tagged the resources), update the Terraform config to match:

```hcl
resource "aws_s3_bucket" "data" {
  bucket = "company-data-${random_id.suffix.hex}"
  tags = {
    Environment = "production"
    Team        = "engineering"
  }
}
```

**What this does:** The tags in the Terraform config now match what we want. If the console changes added different values, update the config to the correct values. The key insight: Terraform is the source of truth. After fixing the config, the next `terraform apply` will ensure reality matches the config — whether that means keeping manual changes or reverting them.

### Step 3: Fix Bug 2 — Enable versioning in Terraform

Someone enabled bucket versioning via the console, and that's the correct state — production buckets should have versioning enabled. Update the Terraform config:

```hcl
resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id
  versioning_configuration {
    status = "Enabled"
  }
}
```

**What this does:** Changes the versioning configuration from `"Disabled"` to `"Enabled"`. This aligns the Terraform config with the intended state. On the next apply, Terraform will see that versioning is already enabled (matching the console change) and make no changes.

### Step 4: Fix Bug 3 — Handle the deleted security group

The security group was deleted manually via the console, but Terraform's state still references it. There are two approaches:

**Option A: Remove from state and let Terraform recreate it:**

```bash
terraform state rm aws_security_group.app
terraform apply
```

**Option B: Keep the resource in Terraform (recommended) and just apply:**

Since the resource definition is still in `main.tf`, Terraform will detect that the real resource is missing and create a new one on the next apply. If the state entry causes an error during plan, remove it from state first:

```bash
terraform state rm aws_security_group.app
```

Then run:

```bash
terraform plan
terraform apply
```

**What this does:** `terraform state rm` removes the resource from Terraform's state file without touching real infrastructure (the resource is already deleted). The resource definition is still in `main.tf`, so the next `terraform apply` creates a brand new security group.

### Step 5: Apply and verify

```bash
terraform plan
terraform apply
```

**What this does:** Shows the planned changes and applies them. After applying:
- S3 bucket has correct tags
- Bucket versioning is enabled
- Security group is recreated
- State matches reality matches configuration

### Step 6: Verify the state is clean

```bash
terraform plan
```

**What this does:** After a successful apply, running plan again should show "No changes." This confirms there's no remaining drift — Terraform's config, state, and reality are all aligned.

### Step 7: Run validation

```bash
./validate.sh
```

**What this does:** Runs `terraform validate` and `terraform plan` to confirm the configuration is valid and produces no errors.

## Docker Lab vs Real Life

- **Remote state:** In production, Terraform state is stored remotely (S3 + DynamoDB, Terraform Cloud, etc.), not locally. Remote state has versioning, so you can recover from state corruption by restoring a previous version.
- **State locking:** DynamoDB (or similar) prevents concurrent state modifications. Without locking, two engineers running `terraform apply` simultaneously can corrupt the state.
- **`terraform apply -refresh-only`:** In Terraform 0.15.4+, this replaces `terraform refresh`. It updates the state to match reality and shows you what changed, without making any infrastructure modifications. Use this when manual changes should be preserved.
- **Preventing manual changes:** In production, enforce infrastructure changes through Terraform only. Use AWS Config rules, SCPs (Service Control Policies), or IAM policies to restrict console access. Some teams use "break glass" procedures that require approval for console access.
- **Drift detection:** Tools like Terraform Cloud, Spacelift, or custom CI/CD pipelines can automatically detect drift by running `terraform plan` on a schedule and alerting when changes are detected.

## Key Concepts Learned

- **Terraform state is Terraform's view of reality** — it records what resources Terraform manages and their current attributes. When someone changes resources outside Terraform, the state becomes stale.
- **`terraform plan` detects drift** — it compares config vs state vs reality and shows the differences. This is your primary diagnostic tool for state issues.
- **`terraform state rm` removes a resource from management** — it doesn't delete the real resource. Use it when a resource was deleted outside Terraform and you need to clean up the state.
- **Decide the source of truth for each drift** — some manual changes should be kept (update config to match), others should be reverted (let Terraform apply revert them). There's no one-size-fits-all answer.
- **Versioning is a best practice for S3 buckets** — it protects against accidental deletions and overwrites. The manual change to enable versioning was correct, so we update the Terraform config to match.

## Common Mistakes

- **Running `terraform apply` without understanding the plan** — Terraform might revert intentional manual changes. Always read the plan carefully before applying.
- **Deleting and recreating resources unnecessarily** — for tag drift or configuration drift, updating the Terraform config is usually enough. You don't need to destroy and recreate the resource.
- **Forgetting to `terraform state rm` before recreating deleted resources** — if a resource was deleted manually and you try to apply, Terraform may error because it tries to read a resource that doesn't exist. Remove it from state first.
- **Using `terraform import` when it's not needed** — import is for bringing existing resources INTO Terraform management. If the resource was already managed by Terraform and just has drift, you don't need import — refresh and config updates handle it.
- **Not enabling state locking in production** — without locking, concurrent applies can corrupt the state file. Always use remote state with locking in team environments.
