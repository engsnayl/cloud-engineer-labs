# Lab 091: ClickOps Reverse Engineering — Discover & Codify

**Difficulty:** ⭐⭐⭐ (Advanced)  
**Time:** 35-45 minutes  
**Category:** Terraform / AWS / Infrastructure as Code  
**Skills:** terraform import, terraform state, AWS CLI discovery, resource documentation, IaC migration strategy

---

## Scenario

A startup has been running on AWS for 3 years. The original engineer built everything by clicking through the AWS console. That engineer left 6 months ago and nobody documented anything. The company now needs to bring on enterprise clients who require proof that infrastructure is version-controlled and auditable.

You've been brought in to reverse-engineer the entire environment, document what exists, and bring it under Terraform management.

> **PROJECT-IAC-001**: "We need our infrastructure in code. We can't confidently change anything right now because nobody knows what depends on what. An auditor asked to see our infrastructure-as-code repo last week and we had nothing to show them."

---

## What You'll Find

The `setup.sh` script simulates the ClickOps engineer — it creates real AWS resources via the CLI (the way a console click would behind the scenes). Once you run it, you'll have a small AWS environment with no Terraform state and no `.tf` files describing it.

Your job is to:
1. **Discover** what resources exist using AWS CLI commands
2. **Document** what you find (use `DISCOVERY.md` as your worksheet)
3. **Write Terraform code** to describe each resource
4. **Import each resource** into Terraform state
5. **Verify** that `terraform plan` shows no changes — meaning your code perfectly matches reality

---

## How to Use This Lab

```bash
# Step 1 — Run the setup script to create the "ClickOps" environment
./setup.sh

# Step 2 — Discover what was created (the script will NOT tell you)
#          Use AWS CLI commands to find resources
#          Document everything in DISCOVERY.md

# Step 3 — Write main.tf to describe what you found

# Step 4 — Import each resource into Terraform state
#          terraform import aws_<resource_type>.<name> <resource_id>

# Step 5 — Iterate until terraform plan shows "No changes"

# Step 6 — Validate
./validate.sh
```

---

## Rules

- You must NOT read `setup.sh` before attempting the lab — that's cheating. In real life nobody hands you a list of what was built. You have to discover it.
- You CAN (and should) use AWS CLI, AWS console, or any discovery tool to find resources.
- All resources were created with a tag `Project = clickops-lab-091` — use this to scope your discovery.

---

## Cleanup

```bash
./teardown.sh
```

This destroys all resources created by the lab. Always run this when you're done — these are real AWS resources that cost money.

---

## Validation

```bash
./validate.sh
```
