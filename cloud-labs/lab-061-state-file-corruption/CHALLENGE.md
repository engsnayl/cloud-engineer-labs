# Lab 061 — Terraform State Mismatch (Drift Detection)

**Difficulty:** ⭐⭐⭐ (Advanced)
**Time:** 25–30 minutes
**Category:** Terraform / State
**Skills:** terraform plan, terraform state rm, state drift, config reconciliation

---

## Scenario

> **INCIDENT-TF-002:** Terraform plan shows it wants to destroy and recreate resources that should stay. Someone made manual changes via the AWS console. State is out of sync with reality.

Infrastructure was previously applied. Since then, changes were made directly in the AWS console without going through Terraform. The config hasn't been updated. Your job is to reconcile everything.

---

## Lab Setup

> ⚠️ **This lab requires a real AWS account. Charges may apply — all resources should be destroyed at the end.**

### Step 1: Initialise and apply

```bash
terraform init
terraform apply
```

This creates the real AWS infrastructure. Terraform's state file is written after apply — this is your baseline.

### Step 2: Simulate the console changes

Someone has just gone into the AWS console and made changes without telling anyone. Run this script to replicate what they did:

```bash
chmod +x corrupt-state.sh
./corrupt-state.sh
```

The script will tell you what it did. Terraform's state file is now out of date.

### Step 3: Detect the drift

```bash
terraform plan
```

Read the output carefully. Your job starts here.

---

## Objectives

1. Read and interpret `terraform plan` output — identify each type of drift
2. Fix the S3 bucket tags in `main.tf` to match the intended production values
3. Fix the versioning configuration in `main.tf` to reflect the console change
4. Understand how Terraform handles a resource that was deleted outside of Terraform
5. `terraform validate` must pass
6. `terraform plan` must complete without errors

---

## Validation

```bash
./validate.sh
```

> 💡 **After validation passes:** Run `terraform destroy` to tear down all resources, then clean up your local Terraform files ready for a fresh run next time:
>
> ```bash
> terraform destroy
> rm -f terraform.tfstate terraform.tfstate.backup
> rm -rf .terraform
> rm -f .terraform.lock.hcl
> ```
>
> The lab directory will be back to its clean starting state for next time.
