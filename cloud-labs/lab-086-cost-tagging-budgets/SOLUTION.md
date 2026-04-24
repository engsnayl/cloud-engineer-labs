# Lab 086 — Cost Tagging & Budgets: Solution Walkthrough

---

## TLDR (Plain English)

**The situation:** Finance can't figure out why the AWS bill jumped 40% last month. Nobody tagged anything properly, so Cost Explorer just shows "untagged" spend with no breakdown by team or project. On top of that, the billing alarm that's *supposed* to warn us about overspend is firing constantly — or looks like it should be — because someone set it to alert at $0. But when we actually investigate, the alarm is stuck in `INSUFFICIENT_DATA` state because it was deployed in the wrong region entirely. And the budget that's meant to notify finance at 80% and 100% of spend has no notifications configured at all. It exists as a number in AWS. That's it.

**What's actually wrong:** Six related gaps across the cost governance setup.

1. Provider has no `default_tags` — nothing gets auto-tagged.
2. Individual resources (VPC, subnet, S3, SNS) aren't tagged at all.
3. The budget has no notification block — silent number in a dashboard.
4. Billing alarm threshold is `0` — would fire constantly (if it could fire at all).
5. SNS topic isn't tagged either — even the alerting infrastructure lacks cost attribution.
6. Billing alarm is in `eu-west-2`, but `AWS/Billing` metrics only publish to `us-east-1` — the alarm can never evaluate and sits inert.

**What we're going to do:** Add `default_tags` to the provider as a safety net. Add explicit `tags = local.common_tags` to every resource (belt-and-braces). Wire notifications into the budget at 80% and 100%. Raise the alarm threshold to match the budget ceiling (10,000 USD). Tag the SNS topic. Add a second aliased AWS provider pointing to `us-east-1` and move the billing alarm to reference it, because that's the only region where billing metrics exist.

**Why `default_tags` AND explicit resource tags?** Belt-and-braces. `default_tags` catches resources a developer forgot; explicit tags make intent visible in the code review.

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
cd ~/cloud-engineer-labs/cloud-labs/lab-086-cost-tagging-budgets
ls -la
```

**What you're looking at:**

| Component | Purpose |
|---|---|
| `cd` | Change directory to the lab folder — puts you in the Terraform working directory |
| `ls -la` | Lists all files including hidden ones (`-l` long format, `-a` all files) |

You see: `main.tf`, `CHALLENGE.md`, `validate.sh`, and a `.terraform/` lock directory if someone's already run `terraform init` here.

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

**What you see:** Two VPCs (the default AWS VPC and yours), both with `None` in the Tags column.

You can't even tell which one is yours from this output alone. That's exactly finance's problem.

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

> **Note:** If you're running this lab fresh and haven't applied yet, `aws s3 ls | grep app-assets` returns nothing and the command fails with a different error (`--bucket: expected one argument`). That just means the bucket doesn't exist yet. Apply the broken Terraform first (`terraform apply`) to create the resources, then continue.

At this point you've confirmed three things from three different angles:
- `common_tags` local is dead code (grep)
- No `default_tags` safety net (grep)
- Live AWS resources are genuinely untagged (AWS CLI)

**That's bug #1 (missing `default_tags`) AND bug #2 (resources not tagged via local).** The root cause is the same — nobody wired tagging up when this was built. The fix is both: add `default_tags` *and* explicit `tags = local.common_tags` on each resource.

### Step 2d: Now look at the Budget

Finance said "no visibility." You know the budget exists because you read it in `main.tf`. But does it actually alert anyone?

```bash
aws budgets describe-budgets \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --region eu-west-2
```

| Component | Purpose |
|---|---|
| `aws budgets describe-budgets` | List budgets (Budgets API is per-account, not per-region) |
| `--account-id $(...)` | Budgets API requires the account ID explicitly |
| `aws sts get-caller-identity --query Account` | Get *your* account ID from the current credentials |
| `--output text` | Plain text so it can be used directly as a parameter value |

**What you see:** The `monthly-account-budget` exists with a 10,000 USD limit. Good — it's real. You may also see pre-existing budgets in your account (e.g. a personal safety budget you set up yourself). Ignore those.

Now the notifications:

```bash
aws budgets describe-notifications-for-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget-name monthly-account-budget \
  --region eu-west-2
```

**What you see:**

```json
{ "Notifications": [] }
```

**Bug #3 confirmed.** The budget is a number sitting in a dashboard. It notifies nobody.

You go back to `main.tf` and confirm the code matches:

```bash
grep -A 10 "aws_budgets_budget" main.tf
```

You see a resource block with name, budget_type, limit_amount, limit_unit, time_unit — and then it closes. **No `notification { ... }` block.** Matches AWS state.

---

## Step 3 — Act Two: The Alarm Noise (INCIDENT-COST-001)

Finance thread is diagnosed. Now the PagerDuty ticket — the billing alarm firing 47 times. You already saw the alarm in `main.tf`. Let's check its live state.

### Step 3a: Start where the metric actually lives

Here's an AWS fact you need to have in your head: **the `AWS/Billing` namespace only publishes metrics in `us-east-1`.** Doesn't matter that your whole estate is in London. Billing data is in N. Virginia. Full stop. So that's where any billing alarm *should* live.

```bash
aws cloudwatch describe-alarms \
  --alarm-names monthly-billing-alarm \
  --region us-east-1 \
  --query 'MetricAlarms[*].[AlarmName,Threshold,StateValue,StateReason]' \
  --output table
```

**What you see:** Nothing. Empty output. The alarm doesn't exist in `us-east-1`.

That's immediately weird. The PagerDuty ticket said the alarm is firing, so it has to exist somewhere. Maybe someone created it in the wrong region?

### Step 3b: Check the region the provider actually points to

```bash
aws cloudwatch describe-alarms \
  --alarm-names monthly-billing-alarm \
  --region eu-west-2 \
  --query 'MetricAlarms[*].[AlarmName,Threshold,StateValue,StateReason]' \
  --output table
```

**What you see:**

```
| monthly-billing-alarm | 0.0 | INSUFFICIENT_DATA | Unchecked: Initial alarm creation |
```

Now you have two findings at once:

**Bug #4 — Threshold is 0.0.** If it could fire, it would fire constantly at any spend above zero. Classic alert-fatigue cause.

**Bug #6 — The alarm is in eu-west-2, but StateValue is `INSUFFICIENT_DATA`.** This is the bigger problem. The alarm was created in London, but billing metrics only publish in N. Virginia. So the alarm has nothing to evaluate against. It's been sitting in `INSUFFICIENT_DATA` since it was created. It has *never* fired.

**Wait — but the PagerDuty ticket said it's firing 47 times?** Re-read the ticket. Sometimes the ticket reflects a perception, not reality ("the alarm channel is noisy" → assumed to be this alarm, but actually noise from something else, or the ticket is wrong). This is a useful real-world lesson: your tickets are hypotheses, not facts. Verify before you act.

Either way — the alarm is broken in two independent ways. It needs both the threshold fixed *and* to be deployed in the correct region.

### Why does `AWS/Billing` only live in `us-east-1`?

Historical. AWS consolidated billing data publication to `us-east-1` for simplicity and global rollups. This predates the multi-region service patterns that came later, and it's never changed. It applies to:
- `AWS/Billing` metrics
- CloudWatch billing alarms (because they consume those metrics)
- Cost allocation tag activation (console only, no regional endpoint)
- AWS Budgets (per-account, no regional endpoint at all)

**Rule of thumb:** anything cost/billing-related in AWS, assume `us-east-1` or global until proven otherwise.

### Why have both a Budget AND a Billing Alarm?

They overlap but serve different roles:

| Tool | Refresh rate | Best for |
|---|---|---|
| AWS Budget | Daily | Planned alerts at progressive thresholds (80%, 100%, forecast) |
| CloudWatch Billing Alarm | Every 6 hours | Faster catch of sudden spikes |

Defence in depth. Budgets are your normal governance; the billing alarm is your "something went very wrong suddenly" tripwire.

### Step 3c: Final check — is the SNS topic tagged?

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
> 4. Billing alarm threshold is `$0` — would fire constantly if it could.
> 5. SNS topic untagged — meta-infra missing cost attribution.
> 6. Billing alarm is in eu-west-2, but `AWS/Billing` metrics only publish to us-east-1 — alarm is stuck in INSUFFICIENT_DATA and has never actually evaluated.
>
> **Proposed fix:** Add `default_tags` to provider (safety net), add explicit `tags = local.common_tags` on every resource (visibility), add 80% + 100% notifications to budget, raise alarm threshold to 10000, add aliased `us-east-1` provider and move billing alarm to it, tag SNS topic.
>
> **Impact of fix on live state:** The alarm will be destroyed in eu-west-2 and recreated in us-east-1. No other destroy operations expected.
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

**Why this matters:** Any AWS resource Terraform creates in this project now inherits these five tags automatically. Even if a future developer forgets to add `tags = ...` to a new resource, it still ends up tagged.

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

### Fix 4 & 6 — Add aliased us-east-1 provider and move the billing alarm

This is two fixes in one because they're inseparable — you can't fix the region without adding a provider, and there's no point fixing the threshold if the alarm can't evaluate.

**Step 4/6a: Add a second provider block**

Underneath your first provider block, add:

```hcl
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

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

| Component | Purpose |
|---|---|
| `alias = "us_east_1"` | Names this provider configuration so resources can opt in to it |
| `region = "us-east-1"` | The region this provider targets |
| `default_tags` | Duplicated — provider configurations don't share this; each needs its own |

**Step 4/6b: Modify the billing alarm to reference the aliased provider**

```hcl
resource "aws_cloudwatch_metric_alarm" "billing" {
  provider = aws.us_east_1

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

**Two changes:**
- Added `provider = aws.us_east_1` at the top of the resource — this tells Terraform to use the aliased provider instead of the default.
- Changed `threshold = 0` to `threshold = 10000` (matching the budget ceiling).

**Expected plan behaviour:** When you run `terraform plan`, you'll see the alarm marked for replacement: `-/+ resource "aws_cloudwatch_metric_alarm" "billing"` with the cause being the provider change. **This is expected.** CloudWatch alarms cannot be moved between regions in place — they have to be destroyed and recreated.

**Heads up about the SNS topic reference:** The alarm's `alarm_actions` references `aws_sns_topic.billing_alerts.arn`. The SNS topic lives in eu-west-2 (default provider). **Cross-region SNS from a CloudWatch alarm is supported** — the alarm in us-east-1 will successfully publish to an SNS topic in eu-west-2. AWS handles the cross-region delivery internally.

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
- `~` (tilde) next to resources — in-place updates. Expect these for VPC, subnet, S3 bucket, budget, SNS topic.
- `-/+` (destroy and recreate) for the **billing alarm only** — expected, because it's changing region.
- No other destroys. If you see anything else marked for destroy, stop and investigate.
- Summary at the bottom: `Plan: 1 to add, N to change, 1 to destroy.` (the add and destroy are both the alarm — it's being recreated in the new region).

Assuming it looks right:

```bash
terraform apply
```

Type `yes` at the prompt.

> **Note on provider initialization:** If you get an error about an unknown provider `aws.us_east_1` during plan, run `terraform init` again. Terraform needs to re-register the aliased provider.

---

## Step 7 — Verify The Fix In Live State

Don't trust Terraform's "Apply complete" line alone. Verify AWS actually reflects what you asked for.

### Tags on VPC:

```bash
aws ec2 describe-vpcs --region eu-west-2 --query 'Vpcs[*].[VpcId,Tags]' --output table
```

Your VPC should now show the five tags (the default AWS VPC still won't, which is how you tell them apart).

### Budget notifications:

```bash
aws budgets describe-notifications-for-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget-name monthly-account-budget \
  --region eu-west-2
```

You should see two notifications — one at 80, one at 100.

### Alarm is in us-east-1 AND has correct threshold:

```bash
# Check us-east-1 — should find the alarm
aws cloudwatch describe-alarms \
  --alarm-names monthly-billing-alarm \
  --region us-east-1 \
  --query 'MetricAlarms[*].[AlarmName,Threshold,StateValue]' \
  --output table

# Check eu-west-2 — should be empty now
aws cloudwatch describe-alarms \
  --alarm-names monthly-billing-alarm \
  --region eu-west-2 \
  --query 'MetricAlarms[*].AlarmName' \
  --output text
```

First command: alarm exists, threshold is `10000.0`. StateValue may be `INSUFFICIENT_DATA` initially (CloudWatch needs one evaluation period to get billing data) — check again in 6+ hours and it should be `OK` assuming spend is well under 10k.

Second command: empty output. The old alarm has been destroyed.

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

All 19 checks should pass (plus 2 live state checks if AWS credentials are configured).

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

| In this lab | In real production |
|---|---|
| Five tags defined in code | 10–20+ tags, often including `Owner`, `DataClassification`, `PII`, `BusinessUnit`, `Compliance` |
| One account | 20+ accounts under AWS Organizations, tags enforced via SCPs and tag policies |
| Tags added after the fact | Tagging is enforced at provisioning time — untagged resources get blocked or auto-remediated |
| Budget notifies one email | Budgets notify distribution lists, post to Slack via SNS → Lambda, and ticket JIRA |
| One budget | Per-team budgets, per-project budgets, per-environment budgets, consolidated org-level budget |
| Email subscription | PagerDuty for critical, Slack for warnings, email only for monthly digests |
| Cost allocation done post-hoc | Finance uses a dedicated FinOps tool (CloudZero, Vantage, CloudHealth) for real-time breakdown |
| USD budget | Organisation would deal with FX conversion — AWS bills in USD, finance reports in GBP. Real finance team headache. |
| Email subscription "just works" | Email subscribers must *manually confirm* the SNS subscription by clicking a link. Until they do, no emails arrive. |
| No drift detection on tagging | AWS Config rules check for required tags; non-compliant resources generate findings |
| Aliased provider for us-east-1 sitting in main.tf | Billing/cost resources usually extracted into a dedicated `billing/` module, with the aliased provider scoped there |
| PagerDuty ticket content matched reality | Tickets are hypotheses — "alarm is firing 47 times" may actually mean "someone saw alarm noise and assumed it was this one." Always verify. |

---

## 🛑 CLEANUP — Destroy All Resources

**Read this section carefully. Leaving resources running costs money. The whole point of this lab is cost awareness.**

### Pre-cleanup: Empty the S3 bucket

```bash
aws s3 rm s3://$(aws s3 ls | grep app-assets | awk '{print $3}') --recursive
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

This will destroy across both regions — the CloudWatch alarm in us-east-1 and everything else in eu-west-2. Terraform handles cross-region destroys in a single operation.

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
# VPC in eu-west-2 (your one, tagged Project=web-platform)
aws ec2 describe-vpcs --region eu-west-2 --filters "Name=tag:Project,Values=web-platform" --query 'Vpcs[*].VpcId' --output text

# Budget (global)
aws budgets describe-budgets --account-id $(aws sts get-caller-identity --query Account --output text) --query 'Budgets[?BudgetName==`monthly-account-budget`].BudgetName' --output text

# Alarm in us-east-1 (where we fixed it to)
aws cloudwatch describe-alarms --alarm-names monthly-billing-alarm --region us-east-1 --query 'MetricAlarms[*].AlarmName' --output text

# Alarm in eu-west-2 (in case anything lingered)
aws cloudwatch describe-alarms --alarm-names monthly-billing-alarm --region eu-west-2 --query 'MetricAlarms[*].AlarmName' --output text

# SNS topic
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
- **Billing metrics live in `us-east-1`** — always, regardless of where your resources are. CloudWatch billing alarms must live there too, or they sit in `INSUFFICIENT_DATA` forever.
- **Aliased providers** — the standard Terraform pattern for multi-region resources within a single configuration. Each alias needs its own `default_tags` since provider configs don't share them.
- **Cross-region CloudWatch → SNS works** — alarm in us-east-1 can publish to SNS topic in eu-west-2 without issue.
- **Alert fatigue is a real failure mode** — a $0 threshold alarm that fires constantly gets muted and becomes worse than no alarm at all. (And, ironically, even worse if the alarm is also in the wrong region — then it looks like it's firing but isn't, and you lose trust in the tooling entirely.)
- **Tag everything, including meta-infrastructure** — SNS topics, CloudWatch alarms, KMS keys, IAM roles. If it costs anything, it should be attributable.
- **Verify tickets against reality** — incident tickets describe perceptions, not facts. Always check live state before acting.

---

## Common Mistakes

- **Only using `tags = local.common_tags` without `default_tags`** — one missed resource breaks cost allocation.
- **Only using `default_tags` without explicit `tags`** — code reviewers can't see tagging intent at the resource.
- **Hardcoding tag values in each resource instead of referencing a `locals` block** — when CostCentre changes, you update 50 places instead of one.
- **Alerting only at 100%** — too late. 50/80/100 is a typical pattern.
- **Forgetting to activate cost allocation tags** — tags are applied but Cost Explorer shows nothing.
- **Setting billing alarm in the wrong region** — if you create it in `eu-west-2` it will never fire. Must be `us-east-1`. The alarm will look "created" in Terraform state but sit in `INSUFFICIENT_DATA` in AWS.
- **Forgetting to duplicate `default_tags` on the aliased provider** — the aliased provider won't inherit anything from the default provider; you have to set default_tags on each independently.
- **Running `terraform apply` without re-running `terraform init`** after adding a new aliased provider — init is what registers the new provider instance.
- **USD vs GBP confusion** — AWS bills in USD. If finance thinks in GBP, make the FX assumption explicit (budget of 10,000 USD ≈ 7,900 GBP at the current rate — but the rate changes).
- **Not confirming SNS email subscriptions** — email subscribers must click a confirmation link. Until then, no alerts arrive even though Terraform says everything is deployed.
- **Leaving the bucket non-empty before destroy** — `terraform destroy` will fail and you'll have to clean up manually.
