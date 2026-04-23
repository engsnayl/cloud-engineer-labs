# Lab 086 — Cost Tagging & Budgets: Solution Walkthrough

---

## TLDR (Plain English)

**The situation:** Finance can't figure out why the AWS bill jumped 40% last month. Nobody tagged anything properly, so Cost Explorer just shows "untagged" spend with no breakdown by team or project. On top of that, the billing alarm that's *supposed* to warn us about overspend is firing constantly because someone set it to alert at $0 — so everyone ignores it. And the budget that's meant to notify finance at 80% and 100% of spend has no notifications configured at all. It exists as a number in AWS. That's it.

**What's actually wrong:** Five related gaps across the cost governance setup.

1. Provider has no `default_tags` — nothing gets auto-tagged.
2. Individual resources (VPC, subnet, S3, SNS) aren't tagged at all.
3. The budget has no notification block — silent number in a dashboard.
4. Billing alarm threshold is `0` — fires immediately and constantly, ignored as noise.
5. Even the alerting infrastructure (SNS topic) isn't tagged, so the meta-resources don't get cost-attributed.

**What we're going to do:** Add `default_tags` to the provider as a safety net, add `tags = local.common_tags` to every resource explicitly (belt-and-braces), wire notifications into the budget at 80% and 100%, raise the alarm threshold to match the budget ceiling (10,000 USD), and tag the SNS topic.

**Why both `default_tags` AND explicit resource tags?** Belt-and-braces. `default_tags` catches resources a developer forgot; explicit tags make intent visible in the code review.

---

## Scene Setting — How The Ticket Lands

You're the on-call cloud engineer on a Monday morning. Two things hit your queue in quick succession:

**09:14 — Slack from the Head of Finance:**

> "We got hit for £11,200 last month, up from £8,000. I can't tell finance who's responsible. Cost Explorer just shows one big lump labelled 'untagged'. The CFO wants cost controls and team-level attribution in place by Friday."

**09:22 — PagerDuty ticket INCIDENT-COST-001:**

> "Monthly billing alarm `monthly-billing-alarm` has triggered 47 times in the last 24 hours. Teams have started muting the channel."

You haven't touched this account before. You know it's Terraform-managed and the repo is on the shared laptop. You open a terminal.

---

## Step 1 — Orient Yourself (Before You Change Anything)

Before touching any file, you want to understand what you're looking at. Cardinal rule: don't edit code in a repo you don't understand.

```bash
cd ~/cloud-engineer-labs/labs/lab-086-cost-tagging-and-budgets
ls -la
```

**What you're looking at:**

| Component | Purpose |
|---|---|
| `cd` | Change directory to the lab folder — puts you in the Terraform working directory |
| `ls -la` | Lists all files including hidden ones (`-l` long format, `-a` all files) |

You see: `main.tf`, `CHALLENGE.md`, `validate.sh`, maybe a `.terraform/` lock directory.

**Next question:** What does the Terraform actually describe? You read `main.tf` top to bottom — not to fix anything yet, just to build a mental model.

```bash
cat main.tf
```

Your mental model after reading:
- A VPC with one subnet.
- An S3 bucket with a random suffix.
- An AWS Budget called `monthly-account-budget` with a 10,000 USD monthly limit.
- A CloudWatch billing alarm.
- An SNS topic with one email subscriber (`finance@example.com`).
- A `locals` block defining `common_tags` — but you make a mental note: *is this local actually being used anywhere?*

That last thought is the first thread you pull.

---

## Step 2 — Act One: The Finance Complaint (Tagging Investigation)

Finance said "I can't tell who's responsible." That's a tagging problem. So you investigate tagging first.

### Step 2a: Does `common_tags` actually get applied?

You already noticed the `locals` block defines `common_tags`. A local that's defined but never referenced is dead code. Let's check:

```bash
grep -n "common_tags" main.tf
```

| Component | Purpose |
|---|---|
| `grep` | Text search tool |
| `-n` | Prefix each match with its line number |
| `"common_tags"` | The literal string to search for |
| `main.tf` | The file to search |

**Expected if everything is wired correctly:** You'd see the `locals { ... }` definition plus one `tags = local.common_tags` reference per resource.

**What you actually see:** Just the `locals` block definition. **Zero resources reference it.**

That's your first confirmed finding. The `common_tags` local is dead code. Nothing is tagged.

### Step 2b: Is there a `default_tags` safety net in the provider?

Before you conclude "nothing is tagged," check one more thing. AWS Terraform has a feature where you can set `default_tags` inside the provider block — these get applied to every resource automatically, even if the resource doesn't specify tags. If that's in place, resources might still be getting tagged via that route.

```bash
grep -A 10 'provider "aws"' main.tf
```

| Component | Purpose |
|---|---|
| `grep` | Text search |
| `-A 10` | After — also print 10 lines *after* each match (so we see the provider block body) |
| `'provider "aws"'` | Single-quoted so the double quotes are literal |
| `main.tf` | File to search |

**What you see:**

```hcl
provider "aws" {
  region = "eu-west-2"
}
```

That's it. Just a region. **No `default_tags` block.** So nothing is being tagged via that route either.

### Step 2c: Confirm in live AWS state

You're going to change things, so verify your read of the code by checking what's actually deployed. Engineers who only read code and never check live state miss drift.

```bash
aws ec2 describe-vpcs --region eu-west-2 --query 'Vpcs[*].[VpcId,Tags]' --output table
```

| Component | Purpose |
|---|---|
| `aws ec2 describe-vpcs` | Lists all VPCs in the region |
| `--region eu-west-2` | London region — matches the provider config |
| `--query 'Vpcs[*].[VpcId,Tags]'` | JMESPath expression — pull VpcId and Tags for every VPC |
| `--output table` | Human-readable tabular format (vs default JSON) |

**What you see:** The VPC exists. `Tags` column shows `None` or empty.

Same check for the S3 bucket:

```bash
aws s3api get-bucket-tagging --bucket $(aws s3 ls | grep app-assets | awk '{print $3}') --region eu-west-2
```

| Component | Purpose |
|---|---|
| `aws s3api get-bucket-tagging` | Fetches the tag set on an S3 bucket |
| `--bucket $(...)` | Command substitution — the `$(...)` runs first, result becomes the bucket name |
| `aws s3 ls` | Lists all S3 buckets |
| `grep app-assets` | Filter down to the lab's bucket |
| `awk '{print $3}'` | Print the third field (which is the bucket name in `aws s3 ls` output) |

**What you see:** An error — `NoSuchTagSet: The TagSet does not exist`. That's S3's way of saying "this bucket has no tags at all."

At this point you've confirmed three things from three different angles:
- `common_tags` local is dead code (grep)
- No `default_tags` safety net (grep)
- Live AWS resources are genuinely untagged (AWS CLI)

**That's bug #1 (missing `default_tags`) AND bug #2 (resources not tagged via local).** The root cause is the same — nobody wired tagging up when this was built. The fix is both: add `default_tags` *and* explicit `tags = local.common_tags` on each resource.

### Step 2d: Now look at the Budget

Finance said "no visibility." You know the budget exists because you read it in `main.tf`. But does it actually alert anyone?

```bash
aws budgets describe-budgets --account-id $(aws sts get-caller-identity --query Account --output text) --region eu-west-2
```

| Component | Purpose |
|---|---|
| `aws budgets describe-budgets` | List budgets (Budgets API is per-account) |
| `--account-id $(...)` | Budgets API requires the account ID explicitly |
| `aws sts get-caller-identity --query Account` | Get *your* account ID from the current credentials |
| `--output text` | Plain text so it can be used directly as a parameter value |

**What you see:** The `monthly-account-budget` exists with a 10,000 USD limit. Good — it's real.

Now the notifications:

```bash
aws budgets describe-notifications-for-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget-name monthly-account-budget \
  --region eu-west-2
```

**What you see:** Empty response, or `Notifications: []`.

**Bug #3 confirmed.** The budget is a number sitting in a dashboard. It notifies nobody.

You go back to `main.tf` and confirm the code matches:

```bash
grep -A 10 "aws_budgets_budget" main.tf
```

You see a resource block with name, budget_type, limit_amount, limit_unit, time_unit — and then it closes. **No `notification { ... }` block.** Matches AWS state.

---

## Step 3 — Act Two: The Alarm Noise (INCIDENT-COST-001)

Finance thread is diagnosed. Now the PagerDuty ticket — the billing alarm firing 47 times. You already saw the alarm in `main.tf`. Let's check its live state.

```bash
aws cloudwatch describe-alarms \
  --alarm-names monthly-billing-alarm \
  --region us-east-1 \
  --query 'MetricAlarms[*].[AlarmName,Threshold,StateValue,StateReason]' \
  --output table
```

| Component | Purpose |
|---|---|
| `aws cloudwatch describe-alarms` | Retrieve CloudWatch alarm config and current state |
| `--alarm-names monthly-billing-alarm` | Filter to just this alarm |
| `--region us-east-1` | Billing metrics live in `us-east-1` only — *always* — regardless of where your resources are |
| `--query` | Pull back just the fields you care about |

**Wait — `us-east-1`? But the provider is `eu-west-2`!**

Yes. This is an AWS quirk worth internalising: **the `AWS/Billing` namespace lives exclusively in us-east-1.** Even if your entire estate is in London or Frankfurt, billing metrics and any alarms that consume them must be in N. Virginia. This is a common gotcha that trips people up.

**What you see:**

```
| monthly-billing-alarm | 0.0 | ALARM | Threshold Crossed: ... |
```

**Threshold is 0.0 and state is ALARM.** You've found bug #4. An alarm that fires when estimated charges exceed $0 will fire as soon as literally anything is spent. It's been in ALARM state continuously. No wonder teams muted the channel.

Back to `main.tf`:

```bash
grep -B 1 -A 15 "aws_cloudwatch_metric_alarm" main.tf
```

| Component | Purpose |
|---|---|
| `-B 1` | Before — print 1 line of context before each match |
| `-A 15` | After — print 15 lines after each match |

You see the offending line: `threshold = 0`. Someone either left it as a placeholder or genuinely thought zero made sense. The fix is to set it to match the budget ceiling — **10,000**. The alarm should fire when you're actually approaching budget blow-out, not when you've spent a single cent.

### Why have both a Budget and a Billing Alarm?

Good question to raise here. They overlap but serve different roles:

| Tool | Refresh rate | Best for |
|---|---|---|
| AWS Budget | Daily | Planned alerts at progressive thresholds (80%, 100%, forecast) |
| CloudWatch Billing Alarm | Every 6 hours | Faster catch of sudden spikes |

Defence in depth. Budgets are your normal governance; the billing alarm is your "something went very wrong suddenly" tripwire.

### Step 3a: Final check — is the SNS topic tagged?

The alarm routes to `aws_sns_topic.billing_alerts`. You've got tagging on your mind from Act One. Let's be thorough:

```bash
aws sns list-tags-for-resource \
  --resource-arn $(aws sns list-topics --region eu-west-2 --query 'Topics[?contains(TopicArn, `billing-alerts`)].TopicArn' --output text) \
  --region eu-west-2
```

| Component | Purpose |
|---|---|
| `aws sns list-tags-for-resource` | SNS uses the generic "list-tags-for-resource" pattern, not a topic-specific command |
| `--resource-arn $(...)` | The ARN of the topic, looked up dynamically |
| `aws sns list-topics` | Lists all SNS topics |
| `--query 'Topics[?contains(TopicArn,` `billing-alerts`\`)].TopicArn'` | JMESPath filter for topics containing "billing-alerts" in the ARN |

**What you see:** `{ "Tags": [] }`. **Bug #5 confirmed.** Even the alerting infrastructure itself isn't contributing to cost attribution. If someone later asks "what does our alerting cost us?", nobody will be able to answer.

---

## Step 4 — Summary Of Findings (Before You Fix)

Before writing any code, you summarise what you've found. This is what you'd paste back into Slack as a status update:

> **Finding summary:**
> 1. No `default_tags` in AWS provider — resources don't auto-inherit tags.
> 2. `locals.common_tags` is defined but never referenced — VPC, subnet, S3, SNS all untagged.
> 3. AWS Budget has no notification block — silent number.
> 4. Billing alarm threshold is `$0` — firing constantly, now ignored.
> 5. SNS topic untagged — meta-infra missing cost attribution.
>
> **Proposed fix:** Add `default_tags` (safety net), add explicit `tags = local.common_tags` on every resource (visibility), add 80% + 100% notifications to budget, raise alarm threshold to 10000 (matching budget), tag SNS topic.
>
> ETA 30 minutes including terraform apply.

This is what separates mid-level engineers from juniors — communicating a clear diagnosis *before* changing anything.

---

## Step 5 — The Fix

Open `main.tf` in your editor. `vi main.tf` is the assumed workflow; `nano main.tf` is fine too (`Ctrl+O` → `Enter` → `Ctrl+X` to save and exit).

### Fix 1 — Add `default_tags` to the provider

Replace the provider block with:

```hcl
provider "aws" {
  region = "eu-west-2"

  default_tags {
    tags = {
      Environment = "production"
      Project     = "web-platform"
      Team        = "platform-engineering"
      CostCentre  = "CC-4521"
      ManagedBy   = "terraform"
    }
  }
}
```

**Why this matters:** Any AWS resource Terraform creates in this project now inherits these five tags automatically. Even if a future developer forgets to add `tags = ...` to a new resource, it still ends up tagged. This is your safety net.

### Fix 2 — Add explicit tags to each resource

Despite `default_tags`, you still add explicit tags per resource. Two reasons: (1) explicit tags override defaults if a resource needs a different value; (2) a reviewer reading the code sees tagging intent directly rather than having to trace it back to the provider block.

```hcl
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags       = local.common_tags
}

resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  tags       = local.common_tags
}

resource "aws_s3_bucket" "app_assets" {
  bucket = "app-assets-${random_id.suffix.hex}"
  tags   = local.common_tags
}
```

### Fix 3 — Add notification blocks to the Budget

Progressive alerting — 80% (warn) and 100% (critical). Alerting only at 100% is too late; the bill is already blown.

```hcl
resource "aws_budgets_budget" "monthly" {
  name         = "monthly-account-budget"
  budget_type  = "COST"
  limit_amount = "10000"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["finance@example.com"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["finance@example.com"]
  }
}
```

**Key arguments explained:**

| Argument | What it means |
|---|---|
| `comparison_operator = "GREATER_THAN"` | Fire when spend crosses above the threshold |
| `threshold = 80` | Percentage of the budget limit (so 80% of 10,000 = 8,000 USD) |
| `threshold_type = "PERCENTAGE"` | Threshold is interpreted as a percentage, not an absolute dollar amount |
| `notification_type = "ACTUAL"` | Fire on actual spend (alternative is `FORECASTED` — fires on projected spend) |
| `subscriber_email_addresses` | List of emails — can be multiple |

### Fix 4 — Raise the billing alarm threshold

```hcl
resource "aws_cloudwatch_metric_alarm" "billing" {
  alarm_name          = "monthly-billing-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = 21600
  statistic           = "Maximum"
  threshold           = 10000
  alarm_description   = "Alert when estimated charges exceed monthly budget"
  alarm_actions       = [aws_sns_topic.billing_alerts.arn]

  dimensions = {
    Currency = "USD"
  }
}
```

**The only change is `threshold = 0` → `threshold = 10000`.** Now the alarm fires only when charges approach or exceed the budget ceiling.

### Fix 5 — Tag the SNS topic

```hcl
resource "aws_sns_topic" "billing_alerts" {
  name = "billing-alerts"
  tags = local.common_tags
}
```

---

## Step 6 — Apply The Fix

```bash
terraform plan
```

| Component | Purpose |
|---|---|
| `terraform plan` | Calculate and show the changes Terraform *would* make, without applying them |

**What to look for in the plan output:**
- `~` (tilde) next to resources — indicates **in-place update**. You want to see this for VPC, subnet, S3 bucket, budget, alarm, SNS topic.
- No `-/+` (destroy and recreate) operations — you're adding tags and tweaking config, nothing should need rebuilding.
- Summary at the bottom: `Plan: 0 to add, N to change, 0 to destroy.`

If the summary shows any destroys, stop and read the plan carefully. Something is off.

Assuming it looks right:

```bash
terraform apply
```

Type `yes` at the prompt.

---

## Step 7 — Verify The Fix In Live State

Don't trust Terraform's "Apply complete" line alone. Verify AWS actually reflects what you asked for.

### Tags on VPC:

```bash
aws ec2 describe-vpcs --region eu-west-2 --query 'Vpcs[*].[VpcId,Tags]' --output table
```

You should now see the five tags. The output goes from an empty `Tags` column to a populated list.

### Budget notifications:

```bash
aws budgets describe-notifications-for-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget-name monthly-account-budget \
  --region eu-west-2
```

You should see two notifications — one at 80, one at 100.

### Alarm threshold:

```bash
aws cloudwatch describe-alarms \
  --alarm-names monthly-billing-alarm \
  --region us-east-1 \
  --query 'MetricAlarms[*].[AlarmName,Threshold,StateValue]' \
  --output table
```

Threshold should now be `10000.0`. StateValue may still show `ALARM` temporarily — CloudWatch needs at least one evaluation period to update. Check again in 6+ hours and it should be `OK` (assuming spend is well under 10k).

### SNS topic tags:

```bash
aws sns list-tags-for-resource \
  --resource-arn $(aws sns list-topics --region eu-west-2 --query 'Topics[?contains(TopicArn, `billing-alerts`)].TopicArn' --output text) \
  --region eu-west-2
```

Should now show the five tags.

### Run the lab validator:

```bash
./validate.sh
```

All checks should pass.

---

## Step 8 — One More Thing: Activate Cost Allocation Tags

This is the step most engineers miss, and it's the difference between "we have tags" and "finance can actually slice the bill by them."

**Tags on resources are just metadata. They don't appear as dimensions in Cost Explorer until you activate them in the Billing console.**

This is a manual, one-time step per account:

1. Open AWS Console → Billing → Cost allocation tags.
2. Under "User-defined cost allocation tags," find `Environment`, `Project`, `Team`, `CostCentre`, `ManagedBy`.
3. Select them and click **Activate**.
4. Wait up to 24 hours. New spend after activation will be sliceable by these tags in Cost Explorer.

**Important limitation:** Activation is not retroactive. The spike last month that finance is worried about won't be broken down by these tags — only spend from this point forward will be.

Tell finance that. Manage expectations.

---

## Lab vs Real Life

What this lab does and doesn't capture:

| In this lab | In real production |
|---|---|
| Five tags defined in code | 10–20+ tags, often including `Owner`, `DataClassification`, `PII`, `BusinessUnit`, `Compliance` |
| One account | 20+ accounts under AWS Organizations, tags enforced via SCPs and tag policies |
| Tags added after the fact | Tagging is enforced at provisioning time — untagged resources get blocked or auto-remediated |
| Budget notifies one email | Budgets notify distribution lists, post to Slack via SNS → Lambda, and ticket JIRA |
| One budget | Per-team budgets, per-project budgets, per-environment budgets, consolidated org-level budget |
| Email subscription | Would be PagerDuty for critical, Slack for warnings, email only for monthly digests |
| Cost allocation done post-hoc | Finance uses a dedicated FinOps tool (CloudZero, Vantage, CloudHealth) for real-time breakdown |
| USD budget | Organisation would deal with FX conversion — AWS bills in USD, finance reports in GBP. This is a real finance team headache. |
| Email subscription "just works" | Email subscribers must *manually confirm* the SNS subscription by clicking a link. Until they do, no emails arrive. |
| No drift detection on tagging | AWS Config rules check for required tags; non-compliant resources generate findings |

---

## 🛑 CLEANUP — Destroy All Resources

**Read this section carefully. Leaving resources running costs money. The whole point of this lab is cost awareness.**

### Pre-cleanup: Empty the S3 bucket

```bash
aws s3 rm s3://$(terraform output -raw bucket_name 2>/dev/null || aws s3 ls | grep app-assets | awk '{print $3}') --recursive
```

| Component | Purpose |
|---|---|
| `aws s3 rm` | Delete objects |
| `s3://...` | S3 URI to the bucket |
| `--recursive` | Delete all objects in the bucket (required if the bucket has anything in it) |

Terraform cannot destroy an S3 bucket that contains objects. This step is mandatory even if you think the bucket is empty.

### Destroy the infrastructure:

```bash
terraform destroy
```

Type `yes` at the prompt.

### Reset the repo to broken state for re-runs:

```bash
git checkout -- main.tf
```

| Component | Purpose |
|---|---|
| `git checkout` | Restore a file to its last committed state |
| `--` | Signals "what follows is a filename, not a branch" |
| `main.tf` | The file to restore |

This throws away your fixes and restores the broken starting state, so you (or someone else) can re-run the lab clean.

### Confirm nothing is left behind:

```bash
# VPC
aws ec2 describe-vpcs --region eu-west-2 --filters "Name=tag:Project,Values=web-platform" --query 'Vpcs[*].VpcId' --output text

# Budget
aws budgets describe-budgets --account-id $(aws sts get-caller-identity --query Account --output text) --query 'Budgets[?BudgetName==`monthly-account-budget`].BudgetName' --output text

# Alarm
aws cloudwatch describe-alarms --alarm-names monthly-billing-alarm --region us-east-1 --query 'MetricAlarms[*].AlarmName' --output text

# SNS
aws sns list-topics --region eu-west-2 --query 'Topics[?contains(TopicArn, `billing-alerts`)].TopicArn' --output text
```

All should return empty.

---

## Key Concepts Recap

- **`default_tags` is your safety net** — set it in the provider block so every resource is tagged even if a developer forgets.
- **Explicit tags on resources are your documentation** — they make tagging intent visible to code reviewers.
- **Belt and braces** — use both, not either/or.
- **Cost allocation tags require activation** — they're metadata until you activate them in the Billing console. And activation is not retroactive.
- **Budgets need notifications** — a budget without alerts is a number nobody sees.
- **Progressive alerting** — 80% warn, 100% critical. Don't only alert at 100%; it's too late by then.
- **Billing metrics live in `us-east-1`** — always, regardless of where your resources are. CloudWatch billing alarms must live there too.
- **Alert fatigue is a real failure mode** — a $0 threshold alarm that fires constantly gets muted and becomes worse than no alarm at all.
- **Tag everything, including meta-infrastructure** — SNS topics, CloudWatch alarms, KMS keys, IAM roles. If it costs anything, it should be attributable.

---

## Common Mistakes

- **Only using `tags = local.common_tags` without `default_tags`** — one missed resource breaks cost allocation.
- **Only using `default_tags` without explicit `tags`** — code reviewers can't see tagging intent at the resource.
- **Hardcoding tag values in each resource instead of referencing a `locals` block** — when CostCentre changes, you update 50 places instead of one.
- **Alerting only at 100%** — too late. 50/80/100 is a typical pattern.
- **Forgetting to activate cost allocation tags** — tags are applied but Cost Explorer shows nothing.
- **Setting billing alarm in the wrong region** — if you create it in `eu-west-2` it will never fire. Must be `us-east-1`.
- **USD vs GBP confusion** — AWS bills in USD. If finance thinks in GBP, make the FX assumption explicit (budget of 10,000 USD ≈ 7,900 GBP at the current rate — but the rate changes).
- **Not confirming SNS email subscriptions** — email subscribers must click a confirmation link. Until then, no alerts arrive even though Terraform says everything is deployed.
- **Leaving the bucket non-empty before destroy** — `terraform destroy` will fail and you'll have to clean up manually.
