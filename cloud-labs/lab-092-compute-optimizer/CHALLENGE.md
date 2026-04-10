# Lab 092: Live Right-Sizing with AWS Compute Optimizer

Title: Live Right-Sizing with AWS Compute Optimizer
Difficulty: ⭐⭐⭐⭐ (Advanced)
Time: 45–60 minutes active + up to 12 hours waiting for Compute Optimizer
Category: Terraform / AWS / Cost Management

---

## Prerequisites

- Completed Lab 090 (Cost Optimisation — Right-Sizing & Waste Elimination)
- AWS CLI configured: `aws configure`
- Terraform installed and working
- Default region: `eu-west-2`

---

## Scenario

In Lab 090 you audited a Terraform configuration and identified over-provisioning by reading the code. That is a real and valuable skill — engineers do pre-deployment reviews constantly.

But there is a second, equally important skill: **validating right-sizing decisions with real data**.

In this lab you will deploy the over-provisioned infrastructure, seed 14 days of simulated utilisation history into CloudWatch, enable AWS Compute Optimizer, and use it to generate data-driven right-sizing recommendations — the same workflow a cloud engineer would follow in a real job.

> **Why simulated data?**
> Compute Optimizer needs a minimum of 30 hours of CloudWatch history, and works best with 14 days. Waiting 14 days is not feasible in a lab. The seeding script pushes backdated metric data that CloudWatch accepts as legitimate — this is the same technique used in AWS Training environments. The skill you are practising (reading and acting on Compute Optimizer output) is identical whether the underlying data is real or seeded.

---

## What Gets Deployed

A deliberately over-provisioned environment:

| Resource | Count | Deployed Type | What It Should Be |
|----------|-------|--------------|-------------------|
| Production web servers | 2 | `m5.2xlarge` | `t3.medium` |
| Dev web server | 1 | `m5.xlarge` | `t3.small` |
| Dev workers | 2 | `m5.xlarge` | `t3.small` |

No RDS or S3 is deployed here — those were covered in Lab 090 and do not require running infrastructure to audit.

---

## Objectives

1. Deploy the infrastructure with `terraform apply`
2. Verify instances are running
3. Seed 14 days of CloudWatch CPU metrics using the provided script
4. Opt in to AWS Compute Optimizer
5. Wait for and retrieve right-sizing recommendations
6. Interpret the recommendations correctly
7. Apply one recommendation manually via the CLI
8. Destroy all infrastructure with `terraform destroy`

## What You'll Practise

- Reading and interpreting AWS Compute Optimizer recommendations
- Using `aws cloudwatch put-metric-data` to seed historical metrics
- Applying a right-sizing change via the AWS CLI
- Stopping and starting EC2 instances as part of a cost-aware workflow
- Destroying infrastructure cleanly with `terraform destroy`

---

## Validation

```bash
./validate.sh
```

The validator checks:
- All instances deployed with correct (over-provisioned) types
- CloudWatch metrics present for all instances (14 days)
- Compute Optimizer enrolled
- At least one instance right-sized (type changed from m5 to t3 family)

---

## Important — Cost Warning

This lab creates **real AWS resources that bill real money**.

The five instances in this lab cost approximately **$1.34/hour combined** while running:
- 2× `m5.2xlarge` at $0.384/hour each = $0.768/hour
- 3× `m5.xlarge` at $0.192/hour each = $0.576/hour

Compute Optimizer can take up to 12 hours to generate recommendations. **Do not leave instances running while you wait.** After the seeding script completes, stop all instances — stopped instances do not bill for compute. The solution file walks you through this.

Estimated total cost for the full lab (instances running only during deploy/seed and the final apply step, stopped in between): **under $0.75**.

**Always run `terraform destroy` when completely finished.**

---

## Files in This Lab

```
lab-092/
├── CHALLENGE.md          ← You are here
├── main.tf               ← Infrastructure definition (do not edit)
├── outputs.tf            ← Terraform outputs for instance IDs
├── validate.sh           ← Lab validator
└── scripts/
    ├── seed-metrics.sh   ← Seeds 14 days of CloudWatch data
    └── check-recommendations.sh  ← Polls Compute Optimizer for results
```
