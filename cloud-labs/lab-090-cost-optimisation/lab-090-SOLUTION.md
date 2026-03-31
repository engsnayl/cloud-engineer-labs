# Solution — Lab 090: AWS Cost Optimisation — Right-Sizing & Waste Elimination

---

## TLDR

The infrastructure works fine — nothing is broken. But it's massively over-provisioned. Production web servers are running on hardware designed for heavy compute workloads when they only need basic web serving capacity. Dev instances run 24/7 even though developers only work business hours. The database is on premium high-performance storage that a small app doesn't need. S3 buckets have no cleanup policies so old logs and build artifacts pile up forever. Nothing is tagged so finance can't tell which team is spending what. And several security groups are wide open to the entire internet, which isn't a cost issue but would get flagged in any audit.

---

## Background Theory

### Why Cloud Costs Spiral

AWS charges by the hour (or second) for compute, by the GB for storage, and by the IOPS for database performance. When engineers first build infrastructure, they tend to over-provision "just to be safe" — pick a big instance, give it lots of disk, choose the premium storage tier. This is fine on day one. The problem is nobody goes back to check whether those choices still make sense 6 or 12 months later. AWS themselves estimate the average company wastes 30% or more of their cloud spend.

### Instance Families — What the Letters Mean

| Family | Designed For | Example Use |
|--------|-------------|-------------|
| `t3` | Burstable general purpose — handles spikes but doesn't need sustained CPU | Web servers, small APIs, dev environments |
| `m5` | Fixed general purpose — sustained compute | Application servers, backend processing |
| `r5` | Memory optimised — large RAM | In-memory caches, analytics databases |
| `c5` | Compute optimised — raw CPU | Video encoding, scientific modelling |

The size suffix (`.medium`, `.large`, `.xlarge`, `.2xlarge`) doubles the CPU and RAM each step up. A `t3.medium` has 2 vCPU / 4GB RAM. A `m5.2xlarge` has 8 vCPU / 32GB RAM. The price difference is roughly 10× between those two.

### Storage Types — io1 vs gp3

| Type | What It Is | When You Need It | Relative Cost |
|------|-----------|-----------------|---------------|
| `gp3` | General purpose SSD — 3000 baseline IOPS included free | Most workloads | £ |
| `io1` | Provisioned IOPS — you pay for every IOP above baseline | High-performance databases doing thousands of transactions per second | £££££ |

A small company's MySQL database almost never needs `io1`. The baseline 3000 IOPS that come free with `gp3` are usually more than enough.

---

## Step-by-Step Learning Pathway

### Step 1 — Read the Ticket and Understand What's Being Asked

The CTO hasn't asked you to redesign the architecture. They've said: "find the waste and fix it — but don't break anything in production." That means:

- You need to **identify** waste (fill out COST_AUDIT.md)
- You need to **fix** it (change main.tf)
- You must **not** remove resources production depends on
- You should be able to **explain** the savings to a non-technical person

Before touching anything, open `COST_AUDIT.md` and use it as your working document.

### Step 2 — Audit the EC2 Instances

Open `main.tf` and look at the EC2 instance blocks. Ask yourself these questions for each one:

**Production web servers (`aws_instance.prod_web`)**

- What instance type is it? → `m5.2xlarge` (8 vCPU, 32GB RAM)
- What is this instance doing? → Serving web traffic
- Does a web server for a small company need 32GB of RAM and 8 cores? → Almost certainly not
- What would be appropriate? → `t3.medium` (2 vCPU, 4GB) or `t3.large` (2 vCPU, 8GB) for a small company's web servers
- What about the disk? → 200GB root volume. A web server's OS and application code rarely needs more than 20-30GB
- Recommended change: `t3.medium` with 30GB disk

**Dev web servers (`aws_instance.dev_web`)**

- Same questions apply, but additionally: do dev servers need to run 24/7?
- Developers work roughly 10 hours a day, 5 days a week = 50 hours out of 168
- That means 70% of the time these are running, nobody is using them
- Recommended change: `t3.small` with 20GB disk (dev doesn't need prod-level specs)

**Dev workers (`aws_instance.dev_worker`)**

- 2× `m5.xlarge` for dev workers — same over-provisioning pattern
- Recommended change: `t3.small` or `t3.medium` with 20GB disk

### Step 3 — Audit the Database

Look at `aws_db_instance.main`:

- Instance class: `db.r5.2xlarge` — this is a memory-optimised instance with 8 vCPU and 64GB RAM. That's designed for large-scale analytics or caching workloads
- Storage type: `io1` with 3000 provisioned IOPS — this is premium storage you pay per-IOP for
- Allocated storage: 500GB with auto-scaling to 1000GB
- Does a small company's app database need 64GB RAM and provisioned IOPS? → No
- Recommended change: `db.t3.medium` (2 vCPU, 4GB — suitable for small app databases), `gp3` storage (3000 IOPS included free), reduce allocated storage to 50-100GB

Also notice: the password is hardcoded in plain text. This isn't a cost issue but it's a security red flag you should note in your audit.

### Step 4 — Audit the S3 Buckets

There are four S3 buckets. All have versioning enabled, none have lifecycle policies.

Ask yourself for each bucket:

| Bucket | Do old objects need to stay forever? | Sensible retention? |
|--------|--------------------------------------|-------------------|
| `app-data` | Maybe — this is production application data | Keep versioning, add lifecycle to expire old versions after 90 days |
| `logs` | No — logs older than 30-90 days are rarely useful | Expire objects after 30 days, transition to Glacier after 7 days |
| `backups` | Keep recent backups, archive old ones | Transition to Glacier after 30 days, expire after 365 days |
| `dev-artifacts` | No — dev build artifacts are disposable | Expire after 7-14 days |

To implement a lifecycle policy, add an `aws_s3_bucket_lifecycle_configuration` resource. For example for the logs bucket:

```hcl
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "expire-old-logs"
    status = "Enabled"

    transition {
      days          = 7
      storage_class = "GLACIER"
    }

    expiration {
      days = 30
    }
  }
}
```

### Step 5 — Add Cost Allocation Tags

Look through the entire `main.tf`. Are any resources tagged with `Environment`, `Team`, or `CostCentre`? → No. None of them have any tags at all.

Without tags, AWS Cost Explorer can't break down spend by team or environment. This is exactly why finance can't explain the bill.

Add a `tags` block to every resource that supports it:

```hcl
tags = {
  Environment = "production"
  Team        = "engineering"
  CostCentre  = "ENG-001"
}
```

For dev resources, use `Environment = "development"`.

### Step 6 — Add a Billing Alarm

There's no alerting on spend. The bill crept up 40% and nobody noticed until finance flagged it manually. Add a CloudWatch billing alarm or AWS Budget:

```hcl
resource "aws_budgets_budget" "monthly" {
  name         = "monthly-total"
  budget_type  = "COST"
  limit_amount = "3500"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = ["cloud-team@company.com"]
  }
}
```

This alerts at 80% of a $3,500 monthly budget — giving the team time to investigate before the bill arrives.

### Step 7 — Fix the Security Groups (Bonus)

While auditing costs, you should also flag security issues. Look at:

- **Dev security group**: Ports 0-65535 open to `0.0.0.0/0` — the entire internet can reach every port on every dev server. Restrict to the company's VPC CIDR (`10.0.0.0/16`) or a specific office IP
- **Database security group**: Port 3306 open to `0.0.0.0/0` — the database is reachable from the entire internet. Restrict to only the web server security group

### Step 8 — Validate

```bash
terraform validate
./validate.sh
```

---

## Command Breakdown

### terraform validate

| Part | What It Does |
|------|-------------|
| `terraform` | The Terraform CLI tool |
| `validate` | Checks `.tf` files for syntax errors and internal consistency — does NOT check against AWS |

### aws_s3_bucket_lifecycle_configuration

| Block | What It Does |
|-------|-------------|
| `bucket` | Which S3 bucket this policy applies to |
| `rule` | A single lifecycle rule (you can have multiple) |
| `id` | A human-readable name for the rule |
| `status` | `"Enabled"` or `"Disabled"` — lets you turn rules on/off without deleting them |
| `transition` | Move objects to a cheaper storage class after X days |
| `expiration` | Delete objects entirely after X days |

### aws_budgets_budget

| Block | What It Does |
|-------|-------------|
| `budget_type` | `"COST"` means tracking spend in dollars/pounds |
| `limit_amount` | The budget ceiling |
| `time_unit` | `"MONTHLY"` resets the budget each calendar month |
| `notification` | Who to alert and at what threshold |
| `threshold = 80` | Alert when spend hits 80% of budget (gives you 20% headroom to react) |

---

## Cleanup / Reset

To restore the lab to its original state and try again:

```bash
git checkout -- main.tf
```

This resets `main.tf` to the original wasteful version from the repo.

No `terraform destroy` is needed for this lab — it's a validate-only lab that doesn't create real AWS resources (the validate script checks the file contents, not actual infrastructure).
