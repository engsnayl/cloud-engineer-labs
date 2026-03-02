# Solution Walkthrough — CloudWatch Alarms Misconfigured

## The Problem

CloudWatch alarms should alert the team during outages, but no alarms fired during the last incident. The alarms exist but are misconfigured. There are **four bugs**:

1. **Wrong comparison operator** — the CPU alarm uses `LessThanThreshold` with a threshold of 80%. This triggers when CPU is BELOW 80% — the opposite of detecting high CPU. It should be `GreaterThanThreshold`.
2. **No alarm actions** — the CPU alarm has no `alarm_actions`, so even when it triggers, it doesn't notify anyone. It should send to the SNS topic.
3. **Missing dimensions** — the CPU alarm has no `dimensions` block, so it doesn't monitor any specific instance. Without dimensions, the alarm monitors the aggregate across all instances (which may not be what you want) or nothing at all.
4. **Status check period too long** — the status check alarm uses `period = 3600` (1 hour). This means it evaluates only once per hour, so a brief failure (even 30 minutes) could be missed entirely. It should be 60 seconds.

## Thought Process

When CloudWatch alarms don't fire, an experienced cloud engineer checks:

1. **Comparison operator** — does the alarm trigger on the right condition? `GreaterThanThreshold` for "too high," `LessThanThreshold` for "too low."
2. **Alarm actions** — is the alarm connected to an SNS topic that notifies the team?
3. **Dimensions** — is the alarm scoped to the correct resource? Without dimensions, it may not monitor what you think.
4. **Period and evaluation periods** — how frequently does the alarm evaluate? Short periods catch issues faster.

## Step-by-Step Solution

### Step 1: Fix Bug 1 — Correct the comparison operator

```hcl
# BROKEN
comparison_operator = "LessThanThreshold"    # Triggers when CPU < 80%!

# FIXED
comparison_operator = "GreaterThanThreshold"  # Triggers when CPU > 80%
```

**Why this matters:** The comparison operator determines when the alarm enters ALARM state:
- `GreaterThanThreshold` — actual > threshold (fires when CPU exceeds 80%)
- `LessThanThreshold` — actual < threshold (fires when CPU drops below 80%)
- `GreaterThanOrEqualToThreshold` — actual >= threshold
- `LessThanOrEqualToThreshold` — actual <= threshold

Using the wrong operator makes the alarm fire on the opposite condition — it alerts on normal operation and stays silent during actual problems.

### Step 2: Fix Bug 2 — Add alarm actions

```hcl
# BROKEN — no actions
# alarm_actions = []

# FIXED — notify via SNS
alarm_actions = [aws_sns_topic.alerts.arn]
```

**Why this matters:** An alarm without actions is silent. It changes state (OK → ALARM) but nobody gets notified. The `alarm_actions` list specifies what happens when the alarm enters ALARM state — typically an SNS topic that sends emails, Slack messages, or PagerDuty alerts.

### Step 3: Fix Bug 3 — Add dimensions

```hcl
# BROKEN — no dimensions
# dimensions = {}

# FIXED — scope to specific instance
dimensions = {
  InstanceId = aws_instance.app.id
}
```

**Why this matters:** Dimensions scope the alarm to a specific resource. Without dimensions, the `CPUUtilization` metric from `AWS/EC2` is ambiguous — it could be from any instance. Adding `InstanceId` ensures the alarm monitors only the specific application instance.

### Step 4: Fix Bug 4 — Reduce status check period

```hcl
# BROKEN
resource "aws_cloudwatch_metric_alarm" "status_check" {
  period = 3600    # 1 hour — too slow!
  dimensions = {
    InstanceId = "i-placeholder"    # Hardcoded placeholder!
  }
}

# FIXED
resource "aws_cloudwatch_metric_alarm" "status_check" {
  alarm_name          = "status-check-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60           # Check every minute
  statistic           = "Maximum"
  threshold           = 0
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions = {
    InstanceId = aws_instance.app.id    # Reference actual instance
  }
}
```

**Why this matters:** `period = 3600` means the alarm evaluates the metric once per hour. A status check failure that lasts 30 minutes and self-heals would never be detected. With `period = 60`, the alarm evaluates every minute, catching failures within 1-2 minutes. Also, the dimension now references the actual instance instead of a placeholder string.

### Step 5: The complete fixed configuration

```hcl
resource "aws_cloudwatch_metric_alarm" "cpu" {
  alarm_name          = "high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions = {
    InstanceId = aws_instance.app.id
  }
}

resource "aws_cloudwatch_metric_alarm" "status_check" {
  alarm_name          = "status-check-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions = {
    InstanceId = aws_instance.app.id
  }
}
```

### Step 6: Validate

```bash
terraform validate
terraform plan
```

## Docker Lab vs Real Life

- **SNS subscriptions:** The SNS topic needs subscribers (email, Slack webhook, PagerDuty, Lambda). Creating the topic without subscriptions means nobody receives the notifications.
- **Composite alarms:** Production monitoring uses composite alarms that combine multiple conditions: "CPU > 80% AND memory > 90% for 5 minutes." This reduces false positives.
- **Anomaly detection:** Instead of fixed thresholds, CloudWatch anomaly detection learns normal patterns and alerts on deviations. This handles seasonal traffic patterns automatically.
- **OK actions and insufficient data actions:** Besides `alarm_actions`, configure `ok_actions` (notify when recovered) and `insufficient_data_actions` (notify when metrics stop arriving).
- **Dashboard integration:** Production CloudWatch dashboards visualize alarm states alongside metrics. This provides at-a-glance operational awareness.

## Key Concepts Learned

- **Comparison operator must match the alert condition** — `GreaterThanThreshold` for high CPU, `LessThanThreshold` for low disk space. The wrong operator inverts the alarm.
- **Alarm actions connect alarms to notifications** — without `alarm_actions`, the alarm is silent. Always connect to an SNS topic.
- **Dimensions scope alarms to specific resources** — without dimensions, the alarm may monitor the wrong thing or nothing at all
- **Short periods catch issues faster** — 60-second periods detect issues in minutes. 3600-second periods can miss issues entirely.
- **Use Terraform resource references, not placeholders** — `aws_instance.app.id` is always correct. Hardcoded placeholder strings like `"i-placeholder"` don't monitor anything real.

## Common Mistakes

- **Wrong comparison operator** — `LessThan` vs `GreaterThan` is the most common alarm misconfiguration. Always double-check the operator matches the intent.
- **Forgetting alarm actions** — an alarm that doesn't notify anyone is useless. Always add `alarm_actions` pointing to an SNS topic.
- **Using placeholders in dimensions** — `InstanceId = "i-placeholder"` monitors a non-existent instance. Use Terraform resource references.
- **Period too long for critical alarms** — status check alarms should use 60-second periods. CPU alarms typically use 300 seconds (5 minutes). Match the period to the urgency.
- **Not creating SNS subscriptions** — the SNS topic exists but nobody subscribes to it. Always create `aws_sns_topic_subscription` resources for email, webhook, or Lambda endpoints.
