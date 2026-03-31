# Lab 090: AWS Cost Optimisation — Right-Sizing & Waste Elimination

**Difficulty:** ⭐⭐⭐ (Advanced)  
**Time:** 30-40 minutes  
**Category:** Terraform / AWS / Cost Management  
**Skills:** EC2 right-sizing, S3 lifecycle policies, scheduled scaling, tagging strategy, AWS cost analysis

---

## Scenario

You've just joined a company as their first cloud engineer. The finance team has flagged that the AWS bill has increased 40% over the past quarter and nobody can explain why. The previous engineer left 3 months ago and everything was deployed via Terraform — but nobody has reviewed the infrastructure since.

> **INCIDENT-COST-001**: Monthly AWS spend has jumped from £3,200 to £4,500. Finance wants answers by end of week. CTO says "find the waste and fix it — but don't break anything in production."

Your job is to audit the Terraform configuration, identify the waste, right-size the resources, and implement policies to prevent future cost creep.

---

## What You'll Find

The `main.tf` deploys a typical small-company AWS environment:

- A VPC with public and private subnets
- EC2 instances for production and development workloads
- An RDS database
- S3 buckets for application data, logs, and backups
- A NAT Gateway

The infrastructure works fine — nothing is broken. But it's massively over-provisioned and has no cost controls in place.

---

## Objectives

1. **Audit the infrastructure** — identify every instance of waste or over-provisioning
2. **Right-size EC2 instances** — match instance types to actual workload requirements
3. **Implement S3 lifecycle policies** — automate cleanup of old logs and backups
4. **Schedule dev environments** — dev resources should not run 24/7
5. **Add cost allocation tags** — every resource must be tagged with `Environment`, `Team`, and `CostCentre`
6. **Implement a billing alarm** — alert when monthly spend exceeds a threshold
7. `terraform validate` must pass
8. `terraform plan` must complete without errors

---

## How to Use This Lab

1. Read through `main.tf` carefully — there are no errors, only waste
2. Use the `COST_AUDIT.md` worksheet to document what you find before changing anything
3. Make your changes in `main.tf`
4. Run `terraform validate` to check syntax
5. Run `./validate.sh` to check all optimisation objectives are met

---

## Validation

```bash
./validate.sh
```
