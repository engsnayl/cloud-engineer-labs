# Lab 072 — Terraform Workspace Management

**Difficulty:** ⭐⭐ Intermediate
**Time:** 15–20 minutes
**Category:** Terraform / Workspaces
**Skills:** `terraform.workspace`, environment separation, workspace-aware configuration, state isolation

---

## Scenario

You've been handed an incident ticket from the on-call engineer:

---

> **INCIDENT-TF-006**
> **Priority:** High
> **Reported by:** Platform Team
>
> Production is behaving like staging. Instances are undersized and all environment tags in AWS are showing the wrong environment name — including on resources we know are in production. We manage both environments with Terraform.
>
> Please investigate the Terraform configuration and fix it so each environment deploys with the correct settings.
>
> **Production should be:**
> - Instance type: `t3.large`
> - ASG: min 2, max 10, desired 2
> - Environment tag: `production`
>
> **Staging should be:**
> - Instance type: `t3.micro`
> - ASG: min 1, max 2, desired 1
> - Environment tag: `staging`

---

## Your Starting Point

You have access to the Terraform configuration in this directory. Start by understanding what's here, then follow the trail.

No one is going to tell you where the bug is. Read the code, ask the right questions, and work through it the way you would on a real incident.

---

## Objectives

1. Identify why the Terraform configuration is producing the same output regardless of environment
2. Fix the configuration so each workspace deploys the correct instance type, scaling settings, and environment tag
3. `terraform validate` must pass
4. `terraform plan` must complete without errors and show the correct values per workspace

---

## Hints

Only read these if you're stuck. Try the code first.

<details>
<summary>Hint 1</summary>
List the available Terraform workspaces. Are there more than one? Which one is currently active?
</details>

<details>
<summary>Hint 2</summary>
Read through main.tf carefully. Are any values hardcoded that should vary by environment?
</details>

<details>
<summary>Hint 3</summary>
Terraform has a built-in variable that tells you the name of the currently active workspace. Look into `terraform.workspace` and how a `locals` map can use it to return different values per environment.
</details>

---

## Validation

```bash
lab validate terraform-labs/lab-072-workspace-management
```

**Requires:** Terraform installed. AWS credentials needed for `apply` — `plan` alone is sufficient to validate your fix.
