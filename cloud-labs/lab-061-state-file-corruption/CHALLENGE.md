# Lab 061 — Terraform State Mismatch (Drift Detection)

**Difficulty:** ⭐⭐⭐ (Advanced)
**Time:** 25–30 minutes
**Category:** Terraform / State
**Skills:** terraform plan, terraform state rm, state drift, config reconciliation

---

## Scenario

> **INCIDENT-TF-002:** Terraform plan shows it wants to destroy and recreate resources that should stay. Someone made manual changes via the AWS console. State is out of sync with reality.

Infrastructure was previously applied. Since then, three things happened in the AWS console without going through Terraform:

The Terraform state file reflects the original apply. The config hasn't been updated. Your job is to reconcile everything.

---

## Lab Setup

This lab comes with a pre-baked state file (`terraform.tfstate`) representing what was applied originally. Before starting the exercises, you need to simulate the three console changes.

### Step 1: Initialise

```bash
terraform init
```

### Step 2: Simulate the console changes

Run the corruption script to simulate the security group being manually deleted:

```bash
chmod +x corrupt-state.sh
./corrupt-state.sh
```

Now run `terraform plan` — you should see errors and drift. That's the starting point for this lab.

---

## Objectives

1. Read and interpret `terraform plan` output — identify each type of drift
2. Fix the S3 bucket tags in `main.tf` to match the intended production values
3. Fix the versioning configuration in `main.tf` to reflect the console change
4. Handle the deleted security group using `terraform state rm` then allow Terraform to recreate it
5. `terraform validate` must pass
6. `terraform plan` must complete with expected changes only (no errors, no unintended modifications)

---

## Validation

```bash
./validate.sh
```

Or manually verify with `terraform plan` showing no errors and only expected creates.
