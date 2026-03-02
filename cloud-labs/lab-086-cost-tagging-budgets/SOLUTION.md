# Solution Walkthrough — Cost Tagging & Budgets

## The Problem

No cost visibility due to missing tags, no budget alerts, and a misconfigured billing alarm. There are **five bugs**:

1. **No default_tags in provider** — resources don't automatically inherit standard tags.
2. **Resources not tagged** — VPC, subnet, S3 bucket, and SNS topic have no tags despite `common_tags` local being defined.
3. **Budget has no notifications** — the budget exists but doesn't alert anyone when thresholds are breached.
4. **Billing alarm threshold is $0** — fires immediately and constantly, becoming noise.
5. **SNS topic untagged** — even the alerting infrastructure itself has no cost attribution.

## Step-by-Step Solution

### Step 1: Add default_tags to provider

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

### Step 2: Add tags to all resources

```hcl
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags       = local.common_tags
}
```

Apply `tags = local.common_tags` to every resource. With `default_tags` as a safety net, resources get tagged even if individual tags are missed.

### Step 3: Add budget notifications

```hcl
resource "aws_budgets_budget" "monthly" {
  # ... existing config ...

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = ["finance@example.com"]
  }

  notification {
    comparison_operator       = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = ["finance@example.com"]
  }
}
```

### Step 4: Fix billing alarm threshold

```hcl
threshold = 10000  # Was: 0 — match the budget limit
```

### Step 5: Tag the SNS topic

```hcl
resource "aws_sns_topic" "billing_alerts" {
  name = "billing-alerts"
  tags = local.common_tags
}
```

## Key Concepts Learned

- **default_tags is your safety net** — set it in the provider block to ensure every resource gets tagged, even if a developer forgets.
- **Consistent tagging enables cost allocation** — tags like Environment, Project, Team, and CostCentre map directly to AWS Cost Explorer dimensions.
- **Budgets need notifications** — a budget without alerts is just a number. Configure both forecast and actual spend thresholds.
- **Billing alarms complement budgets** — budgets are checked daily. CloudWatch billing alarms can check every 6 hours for faster response.
- **Tag everything, including infrastructure** — SNS topics, CloudWatch alarms, and other "meta" resources should also be tagged for complete cost attribution.

## Common Mistakes

- **Relying only on manual tagging** — developers forget. Use default_tags, AWS Organizations tag policies, and SCPs to enforce tagging.
- **Not activating cost allocation tags** — tags exist on resources but don't appear in Cost Explorer until activated in the Billing console.
- **Setting alarm thresholds too low** — a $0 threshold means constant alerts, which teams learn to ignore (alert fatigue).
- **Only alerting at 100%** — by the time you hit 100%, it's too late. Alert at 50%, 80%, and 100% for progressive awareness.
- **USD vs GBP mismatch** — AWS billing is in USD. Make sure budget amounts account for currency conversion if your finance team thinks in GBP.
