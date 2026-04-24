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

**What we're going to do:** Add `default_tags` to the provider as a safety net. Add explicit `tags = local.common_tags` to every resource (belt-and-braces). Wire notifications into the budget at 80% and 100%. Raise the alarm threshold to match the budget ceiling (10,000 USD). Tag the SNS topic. And crucially — use AWS provider v6's per-resource `region` attribute to place the billing alarm in `us-east-1`, because the more "obvious" approach (aliased provider) has a long-standing Terraform provider bug that silently ignores the provider override on this resource type.

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

| Component | Purpose |
|---|---|
| `cd` | Change directory to the lab folder — puts you in the Terraform working directory |
| `ls -la` | Lists all files including hidden ones (`-l` long format, `-a` all files) |

You see: `main.tf`, `CHALLENGE.md`, `validate.sh`.

**Next question:** What does the Terraform actually describe? Read `main.tf` top to bottom — not to fix anything yet, just to build a mental model.

```bash
cat main.tf
```

Your mental model after reading:
- A VPC with one subnet.
- An S3 bucket with a random suffix.
- An AWS Budget with a 10,000 USD monthly limit.
- A CloudWatch billing alarm.
- An SNS topic with one email subscriber (`finance@example.com`).
- A `locals` block defining `common_tags` — mental note: *is this local actually being used anywhere?*

### Apply the broken Terraform first

Because the infrastructure doesn't exist yet on your Pi, apply the broken state so you can investigate live AWS state the way a real engineer would:

```bash
terraform init
terraform apply
```

Type `yes`. You should see `Apply complete! Resources: 8 added, 0 changed, 0 destroyed.`

Now you have a live environment that exactly mirrors the real-world scenario — broken cost governance, sitting in production, waiting for you to diagnose.

---

## Step 2 — Act One: The Finance Complaint (Tagging Investigation)

Finance said "I can't tell who's responsible." That's a tagging problem. So you investigate tagging first.

### Step 2a: Does `common_tags` actually get applied?

You noticed the `locals` block defines `common_tags`. A local that's defined but never referenced is dead code. Let's check:

```bash
grep -n "common_tags" main.tf
```

| Component | Purpose |
|---|---|
| `grep` | Text search tool |
| `-n` | Prefix each match with its line number |
| `"common_tags"` | The literal string to search for |
| `main.tf` | The file to search |

**Expected if everything is wired correctly:** the `locals { ... }` definition plus one `tags = local.common_tags` reference per resource.

**What you actually see:** Just the `locals` block definition. Zero resources reference it.

First finding confirmed. The `common_tags` local is dead code. Nothing is tagged.

### Step 2b: Is there a `default_tags` safety net in the provider?

AWS Terraform has a feature where you can set `default_tags` inside the provider block — these get applied to every resource automatically, even if the resource doesn't specify tags. If that's in place, resources might still be getting tagged via that route.

```bash
grep -A 10 'provider "aws"' main.tf
```

| Component | Purpose |
|---|---|
| `-A 10` | After — also print 10 lines *after* each match |
| `'provider "aws"'` | Single-quoted so the double quotes are literal |

**What you see:**

```hcl
provider "aws" {
  region = "eu-west-2"
}
```

Just a region. No `default_tags` block. So nothing is being tagged via that route either.

### Step 2c: Confirm in live AWS state

Engineers who only read code and never check live state miss drift. Verify your read:

```bash
aws ec2 describe-vpcs --region eu-west-2 --query 'Vpcs[*].[VpcId,Tags]' --output table
```

| Component | Purpose |
|---|---|
| `aws ec2 describe-vpcs` | Lists all VPCs in the region |
| `--region eu-west-2` | London region — matches the provider config |
| `--query 'Vpcs[*].[VpcId,Tags]'` | JMESPath expression — pull VpcId and Tags for every VPC |
| `--output table` | Human-readable tabular format |

**What you see:** Two VPCs (the default AWS VPC and yours), both with `None` in the Tags column. You can't even tell which one is yours from this output alone. That's exactly finance's problem.

Same for the S3 bucket:

```bash
aws s3api get-bucket-tagging --bucket $(aws s3 ls | grep app-assets | awk '{print $3}') --region eu-west-2
```

| Component | Purpose |
|---|---|
| `aws s3api get-bucket-tagging` | Fetches the tag set on an S3 bucket |
| `--bucket $(...)` | Command substitution — the `$(...)` runs first, result becomes the bucket name |
| `aws s3 ls` | Lists all S3 buckets |
| `grep app-assets` | Filter to the lab's bucket |
| `awk '{print $3}'` | Print the third field (bucket name in `aws s3 ls` output) |

**What you see:** `NoSuchTagSet: The TagSet does not exist`. S3's way of saying "this bucket has no tags at all."

Three confirmations from three angles:
- `common_tags` local is dead code (grep)
- No `default_tags` safety net (grep)
- Live AWS resources genuinely untagged (AWS CLI)

**That's bug #1 AND bug #2.** Same root cause — nobody wired tagging up when this was built. Fix is both: add `default_tags` *and* explicit `tags = local.common_tags` on each resource.

### Step 2d: Now look at the Budget

Finance said "no visibility." The budget exists. But does it actually alert anyone?

```bash
aws budgets describe-budgets \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --region eu-west-2
```

| Component | Purpose |
|---|---|
| `aws budgets describe-budgets` | List budgets (Budgets API is per-account, not per-region) |
| `--account-id $(...)` | Budgets API requires the account ID explicitly |
| `aws sts get-caller-identity --query Account` | Get *your* account ID from current credentials |
| `--output text` | Plain text so it can be used directly as a parameter value |

**What you see:** The `monthly-account-budget` exists with a 10,000 USD limit. Real. You may also see pre-existing budgets (your own personal safety budget, for example) — ignore those.

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

**Bug #3 confirmed.** The budget is a number in a dashboard that notifies nobody.

Confirm against code:

```bash
grep -A 10 "aws_budgets_budget" main.tf
```

Resource block has name, budget_type, limit_amount, limit_unit, time_unit — then closes. No `notification { ... }` block. Matches AWS state.

---

## Step 3 — Act Two: The Alarm Noise (INCIDENT-COST-001)

Finance thread is diagnosed. Now the PagerDuty ticket.

### Step 3a: Start where the metric actually lives

Key AWS fact: **the `AWS/Billing` namespace only publishes metrics in `us-east-1`.** Doesn't matter where your estate is. Billing data is in N. Virginia. Full stop. So that's where any billing alarm *should* live.

```bash
aws cloudwatch describe-alarms \
  --alarm-names monthly-billing-alarm \
  --region us-east-1 \
  --query 'MetricAlarms[*].[AlarmName,Threshold,StateValue,StateReason]' \
  --output table
```

**What you see:** Nothing. Empty output. The alarm doesn't exist in `us-east-1`.

That's immediately weird. The ticket said the alarm is firing, so it has to exist somewhere.

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

Two findings at once:

**Bug #4 — Threshold is 0.0.** If it could fire, it would fire constantly at any spend above zero. Classic alert-fatigue cause.

**Bug #6 — The alarm is in eu-west-2, and StateValue is `INSUFFICIENT_DATA`.** This is the bigger problem. The alarm was created in London but billing metrics only publish in N. Virginia. The alarm has nothing to evaluate. It's been sitting in `INSUFFICIENT_DATA` since creation. It has *never* fired.

**But the ticket said it's firing 47 times?** Re-read the ticket. Tickets reflect perceptions, not always reality ("the alarm channel is noisy" → assumed to be this alarm, but actually noise from something else, or the ticket is wrong). Real-world lesson: tickets are hypotheses, not facts. Verify before you act.

### Why does `AWS/Billing` only live in `us-east-1`?

Historical. AWS consolidated billing data publication to `us-east-1` for simplicity and global rollups. It applies to:
- `AWS/Billing` metrics
- CloudWatch billing alarms (because they consume those metrics)
- Cost allocation tag activation (console only, no regional endpoint)
- AWS Budgets (per-account, no regional endpoint at all)

**Rule of thumb:** anything cost/billing-related in AWS → assume `us-east-1` or global until proven otherwise.

### Why have both a Budget AND a Billing Alarm?

They overlap but serve different roles:

| Tool | Refresh rate | Best for |
|---|---|---|
| AWS Budget | Daily | Planned alerts at progressive thresholds (80%, 100%, forecast) |
| CloudWatch Billing Alarm | Every 6 hours | Faster catch of sudden spikes |

Defence in depth. Budgets are your normal governance; the billing alarm is your "something went very wrong suddenly" tripwire.

### Step 3c: Final check — is the SNS topic tagged?

```bash
aws sns list-tags-for-resource \
  --resource-arn $(aws sns list-topics --region eu-west-2 --query 'Topics[?contains(TopicArn, `billing-alerts`)].TopicArn' --output text) \
  --region eu-west-2
```

| Component | Purpose |
|---|---|
| `aws sns list-tags-for-resource` | SNS uses the generic "list-tags-for-resource" pattern |
| `--resource-arn $(...)` | The ARN looked up dynamically |
| `--query 'Topics[?contains(TopicArn,` `billing-alerts`\`)].TopicArn'` | JMESPath filter for topics containing "billing-alerts" |

**What you see:** `{ "Tags": [] }`. **Bug #5 confirmed.**

---

## Step 4 — Summary Of Findings (Before You Fix)

> **Finding summary:**
> 1. No `default_tags` in AWS provider — resources don't auto-inherit tags.
> 2. `locals.common_tags` is defined but never referenced — VPC, subnet, S3, SNS all untagged.
> 3. AWS Budget has no notification block — silent number.
> 4. Billing alarm threshold is `$0` — would fire constantly if it could.
> 5. SNS topic untagged — meta-infra missing cost attribution.
> 6. Billing alarm is in eu-west-2, but `AWS/Billing` metrics only publish to us-east-1 — alarm stuck in INSUFFICIENT_DATA, has never actually evaluated.
>
> **Proposed fix:** Add `default_tags` to provider. Add explicit `tags = local.common_tags` on every resource. Add 80% + 100% notifications to budget. Raise alarm threshold to 10000. Use AWS provider v6's `region` attribute to place the alarm in us-east-1. Tag SNS topic.
>
> **Impact on live state:** The alarm will be destroyed in eu-west-2 and recreated in us-east-1. No other destroys expected.
>
> ETA 30 minutes including terraform apply.

---

## Step 5 — The Fix

Open `main.tf`:

```bash
vi main.tf
```

(`nano` works too — `Ctrl+O`, `Enter`, `Ctrl+X` to save and exit.)

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

Despite `default_tags`, add explicit tags per resource. Two reasons: (1) explicit tags override defaults if a resource needs a different value; (2) a reviewer reading the code sees tagging intent directly rather than tracing it back to the provider block.

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
| `notification_type = "ACTUAL"` | Fire on actual spend (alternative is `FORECASTED`) |
| `subscriber_email_addresses` | List of emails — can be multiple |

### Fix 4 & 6 — Move the alarm to us-east-1 and raise the threshold

This is the tricky one. The "textbook" Terraform pattern for multi-region resources is **aliased providers** — declare a second provider with `alias = "us_east_1"` and point the alarm at it. Tempting, and logically correct.

**But there's a long-standing bug in the AWS Terraform provider** affecting `aws_cloudwatch_metric_alarm` specifically: the provider meta-argument is not reliably honoured, and the alarm creation request can get sent to the default provider's region anyway — where AWS rejects it with a validation error:

> `Invalid region eu-west-2 specified. Only us-east-1 is supported.`

This has been open for years (GitHub issues #7371, #1553) and still catches people out in provider v6.

**Use v6's per-resource `region` attribute instead.** It's a feature AWS provider v6 added specifically to work around issues like this — you can tell a single resource to target a different region than its provider, without needing a second provider at all.

```hcl
resource "aws_cloudwatch_metric_alarm" "billing" {
  region = "us-east-1"

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
- `region = "us-east-1"` at the top — places this specific resource in us-east-1, while the rest of the config stays in eu-west-2.
- `threshold = 0` → `threshold = 10000` (matching the budget ceiling).

**Cross-region SNS works fine:** the alarm in us-east-1 can publish to an SNS topic in eu-west-2 via `alarm_actions = [aws_sns_topic.billing_alerts.arn]`. AWS handles the cross-region delivery internally.

**Expected plan behaviour:** The alarm will be marked for replacement: `-/+ resource "aws_cloudwatch_metric_alarm" "billing"`. CloudWatch alarms can't be moved between regions in place — they have to be destroyed and recreated.

### Fix 5 — Tag the SNS topic

```hcl
resource "aws_sns_topic" "billing_alerts" {
  name = "billing-alerts"
  tags = local.common_tags
}
```

---

## Real-World Gotcha Log — Worth Reading

One of the genuinely valuable things to come out of this lab is the debugging experience if you try the aliased-provider approach first (which is what Terraform docs and most tutorials point you to). Here's the sequence of frustrations to expect and what they teach:

1. **You add a second aliased provider block and `provider = aws.us_east_1` to the alarm.** Run `terraform plan`. Plan looks clean. Apply. Apply succeeds. Feels like you're done.

2. **You run the validator.** Live state check fails: alarm is still in eu-west-2. But Terraform said apply succeeded? Check `terraform state show aws_cloudwatch_metric_alarm.billing` — state still says `region = "eu-west-2"`. Terraform did the in-place update (threshold, tags) but didn't recognise the provider change as forcing a region move.

3. **You run `terraform apply -replace="aws_cloudwatch_metric_alarm.billing"` to force it.** Plan shows `-/+` (destroy + recreate). Good. Apply. Destroy succeeds. Create fails with `Invalid region eu-west-2 specified. Only us-east-1 is supported.` Now you have **zero alarms** because the destroy worked but the create didn't.

4. **You check everything.** `terraform validate` says success. `terraform providers` only shows one AWS provider (expected — aliased providers are configurations of the same provider). You run `terraform init -upgrade`. You re-plan, re-apply. Same error.

5. **You search the issue.** Turns out it's a known bug in the provider, open since 2016. The `provider` meta-argument on `aws_cloudwatch_metric_alarm` isn't reliably honoured.

6. **You switch to `region = "us-east-1"` on the resource.** It just works.

**The lesson:** Terraform's "correct" abstraction (aliased providers) has a leaky implementation for some resource types. Knowing workarounds — and knowing when to stop fighting the framework and use a different pattern — is what separates a mid-level engineer from a junior. AWS provider v6 added the per-resource `region` attribute specifically because this class of problem is common enough to warrant a first-class workaround.

Keep this pattern in mind for:
- CloudWatch billing alarms (this lab)
- CloudWatch alarms on global services (Route 53 health checks, CloudFront)
- ACM certificates for CloudFront (must be us-east-1)
- WAFv2 with global scope (us-east-1)

---

## Step 6 — Apply The Fix

```bash
terraform init
terraform plan
```

| Component | Purpose |
|---|---|
| `terraform init` | Re-run if config structure has changed |
| `terraform plan` | Preview changes without applying |

**What to look for:**
- `~` next to VPC, subnet, S3 bucket, budget, SNS topic — in-place updates adding tags/notifications.
- `-/+` next to the **billing alarm** — destroy and recreate because the region changed.
- Summary: `Plan: 1 to add, 5 to change, 1 to destroy.`

If you see anything else marked for destroy, stop and read the plan.

```bash
terraform apply
```

Type `yes`.

---

## Step 7 — Verify The Fix In Live State

Don't trust "Apply complete" alone.

### Tags on VPC:

```bash
aws ec2 describe-vpcs --region eu-west-2 --query 'Vpcs[*].[VpcId,Tags]' --output table
```

Your VPC should now show five tags (the default AWS VPC still won't, which is how you tell them apart).

### Budget notifications:

```bash
aws budgets describe-notifications-for-budget \
  --account-id $(aws sts get-caller-identity --query Account --output text) \
  --budget-name monthly-account-budget \
  --region eu-west-2
```

Should show two notifications — one at 80, one at 100.

### Alarm is in us-east-1:

```bash
aws cloudwatch describe-alarms \
  --alarm-names monthly-billing-alarm \
  --region us-east-1 \
  --query 'MetricAlarms[*].[AlarmName,Threshold,StateValue]' \
  --output table
```

Alarm exists, threshold `10000.0`, StateValue likely `INSUFFICIENT_DATA` initially (billing metrics take time to populate — check again in 6+ hours, should transition to `OK`).

And confirm it's no longer in eu-west-2:

```bash
aws cloudwatch describe-alarms \
  --alarm-names monthly-billing-alarm \
  --region eu-west-2 \
  --query 'MetricAlarms[*].AlarmName' \
  --output text
```

Should return empty.

### SNS topic tags:

```bash
aws sns list-tags-for-resource \
  --resource-arn $(aws sns list-topics --region eu-west-2 --query 'Topics[?contains(TopicArn, `billing-alerts`)].TopicArn' --output text) \
  --region eu-west-2
```

Should show five tags.

### Run the lab validator:

```bash
./validate.sh
```

All config + live state checks should pass.

---

## Step 8 — Activate Cost Allocation Tags (Step Most People Miss)

**Tags on resources are just metadata. They don't appear as dimensions in Cost Explorer until you activate them in the Billing console.**

One-time step per account:

1. AWS Console → Billing → Cost allocation tags.
2. Under "User-defined cost allocation tags," find `Environment`, `Project`, `Team`, `CostCentre`, `ManagedBy`.
3. Select them and click **Activate**.
4. Wait up to 24 hours.

**Important:** Activation is not retroactive. Last month's spike won't be broken down by these tags — only spend from this point forward.

Tell finance that. Manage expectations.

---

## Lab vs Real Life

| In this lab | In real production |
|---|---|
| Five tags defined in code | 10–20+ tags, often `Owner`, `DataClassification`, `PII`, `BusinessUnit`, `Compliance` |
| One account | 20+ accounts under AWS Organizations, tags enforced via SCPs and tag policies |
| Tags added after the fact | Tagging enforced at provisioning time — untagged resources blocked or auto-remediated |
| Budget notifies one email | Distribution lists, Slack via SNS → Lambda, JIRA tickets |
| One budget | Per-team, per-project, per-environment, consolidated org-level |
| Email subscription | PagerDuty for critical, Slack for warnings, email only for digests |
| Cost allocation done post-hoc | FinOps tools (CloudZero, Vantage, CloudHealth) for real-time breakdown |
| USD budget | Organisation would handle FX conversion — AWS bills USD, finance reports GBP. Real headache. |
| Email subscription "just works" | SNS email subscribers must *manually confirm* — no emails until they click the link |
| No drift detection on tagging | AWS Config rules check for required tags; non-compliant resources generate findings |
| PagerDuty ticket content matched reality | Tickets are hypotheses. "Alarm is firing 47 times" may mean "someone saw alarm noise and assumed it was this one." Always verify. |
| Per-resource `region` for one alarm | Billing/cost resources usually extracted into a dedicated module to centralise the workaround |

---

## 🛑 CLEANUP — Destroy All Resources

**Read carefully. Leaving resources running costs money. The whole point of this lab is cost awareness.**

### Pre-cleanup: Empty the S3 bucket

```bash
aws s3 rm s3://$(aws s3 ls | grep app-assets | awk '{print $3}') --recursive
```

| Component | Purpose |
|---|---|
| `aws s3 rm` | Delete objects |
| `s3://...` | S3 URI to the bucket |
| `--recursive` | Delete all objects in the bucket |

Terraform cannot destroy an S3 bucket that contains objects.

### Destroy the infrastructure:

```bash
terraform destroy
```

Type `yes`. This destroys across both regions — the alarm in us-east-1 and everything else in eu-west-2 — in a single operation.

### Reset the repo to broken state for re-runs:

```bash
git checkout -- main.tf
```

| Component | Purpose |
|---|---|
| `git checkout` | Restore a file to its last committed state |
| `--` | Signals "what follows is a filename, not a branch" |
| `main.tf` | The file to restore |

### Confirm nothing is left behind:

```bash
# Your VPC in eu-west-2
aws ec2 describe-vpcs --region eu-west-2 --filters "Name=tag:Project,Values=web-platform" --query 'Vpcs[*].VpcId' --output text

# Budget
aws budgets describe-budgets --account-id $(aws sts get-caller-identity --query Account --output text) --query 'Budgets[?BudgetName==`monthly-account-budget`].BudgetName' --output text

# Alarm in us-east-1
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
- **Cost allocation tags require activation** — they're metadata until activated in the Billing console. Activation is not retroactive.
- **Budgets need notifications** — a budget without alerts is a number nobody sees.
- **Progressive alerting** — 80% warn, 100% critical. Don't only alert at 100%; too late by then.
- **Billing metrics live in `us-east-1`** — always, regardless of where your resources are. CloudWatch billing alarms must too.
- **AWS provider v6 per-resource `region` attribute** — the pragmatic way to handle single-resource region overrides. More reliable than aliased providers for some resource types (notably `aws_cloudwatch_metric_alarm`).
- **Cross-region CloudWatch → SNS works** — alarm in us-east-1 can publish to SNS topic in eu-west-2.
- **Alert fatigue is a real failure mode** — a $0 threshold alarm that fires constantly gets muted and becomes worse than no alarm at all.
- **Tag everything, including meta-infrastructure** — SNS topics, CloudWatch alarms, KMS keys, IAM roles. If it costs anything, it should be attributable.
- **Tickets are hypotheses, not facts** — incident tickets describe perceptions. Always verify live state before acting.
- **Terraform's abstractions can leak** — aliased providers are "correct" but buggy for some resources. Know the workarounds.

---

## Common Mistakes

- **Only using `tags = local.common_tags` without `default_tags`** — one missed resource breaks cost allocation.
- **Only using `default_tags` without explicit `tags`** — code reviewers can't see tagging intent at the resource.
- **Hardcoding tag values in each resource instead of a `locals` block** — when CostCentre changes, update 50 places instead of one.
- **Alerting only at 100%** — too late. 50/80/100 is typical.
- **Forgetting to activate cost allocation tags** — tags applied but Cost Explorer shows nothing.
- **Setting billing alarm in the wrong region** — creates in `eu-west-2` will never fire. Must be `us-east-1`.
- **Using aliased provider for `aws_cloudwatch_metric_alarm`** — known bug, use `region = "us-east-1"` on the resource instead.
- **USD vs GBP confusion** — AWS bills in USD. If finance thinks in GBP, make the FX assumption explicit.
- **Not confirming SNS email subscriptions** — email subscribers must click a confirmation link. Until then, no alerts arrive even though Terraform says everything is deployed.
- **Leaving the bucket non-empty before destroy** — `terraform destroy` will fail and you'll have to clean up manually.
