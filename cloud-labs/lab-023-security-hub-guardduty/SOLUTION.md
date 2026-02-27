# Solution Walkthrough — Security Hub & GuardDuty Misconfigured

## The Problem

The security monitoring pipeline is broken at multiple points. GuardDuty isn't detecting threats, Security Hub isn't aggregating findings, and the alerting pipeline isn't routing critical findings to the security team. There are **five bugs**:

1. **GuardDuty detector is disabled** — `enable = false` means the detector exists but isn't actively monitoring. No findings are generated.
2. **Kubernetes audit logs are disabled** — `enable = false` on the Kubernetes datasource means GuardDuty won't detect threats in EKS clusters.
3. **Security Hub has no GuardDuty integration** — Security Hub needs an explicit product subscription to receive GuardDuty findings. Without `aws_securityhub_product_subscription`, the two services don't talk to each other.
4. **EventBridge rule only matches INFORMATIONAL severity** — the rule filters for "INFORMATIONAL" findings, which are the least important. Critical security events have severity labels of "CRITICAL" and "HIGH".
5. **SNS topic policy has the wrong service principal** — the policy allows `s3.amazonaws.com` to publish, but EventBridge uses `events.amazonaws.com`.

## Thought Process

When a security alerting pipeline isn't working, trace the data flow end-to-end:

1. **Source** — Is GuardDuty actually enabled and monitoring? Check the detector status and data sources.
2. **Aggregation** — Is Security Hub receiving findings? Check product integrations.
3. **Routing** — Is EventBridge matching the right events? Check the event pattern filter.
4. **Delivery** — Can EventBridge publish to the SNS target? Check the topic policy.

## Step-by-Step Solution

### Step 1: Enable GuardDuty

```hcl
resource "aws_guardduty_detector" "main" {
  enable = true  # Was: false
```

**Why:** A GuardDuty detector that isn't enabled is just a placeholder. It won't analyse CloudTrail logs, VPC Flow Logs, or DNS logs, and won't generate any findings.

### Step 2: Enable Kubernetes audit logs

```hcl
kubernetes {
  audit_logs {
    enable = true  # Was: false
  }
}
```

**Why:** With EKS workloads in the environment, you need GuardDuty monitoring Kubernetes audit logs to detect threats like privilege escalation, suspicious API calls, and potentially compromised pods.

### Step 3: Add Security Hub product subscription for GuardDuty

Add this resource after the `aws_securityhub_account`:

```hcl
resource "aws_securityhub_product_subscription" "guardduty" {
  product_arn = "arn:aws:securityhub:${data.aws_region.current.name}::product/aws/guardduty"
  depends_on  = [aws_securityhub_account.main]
}
```

**Why:** Security Hub doesn't automatically ingest findings from other services. You must explicitly subscribe to each product (GuardDuty, Inspector, Macie, etc.) to receive their findings. Without this, the Security Hub console shows "No findings" even though GuardDuty is generating them.

### Step 4: Fix the EventBridge severity filter

```hcl
Label = [
  "CRITICAL",
  "HIGH"
]
```

**Why:** Security Hub uses five severity labels: INFORMATIONAL, LOW, MEDIUM, HIGH, and CRITICAL. A security alerting pipeline should route CRITICAL and HIGH findings for immediate attention. INFORMATIONAL findings are noise in an alerting context.

### Step 5: Fix the SNS topic policy principal

```hcl
Principal = {
  Service = "events.amazonaws.com"  # Was: s3.amazonaws.com
}
```

**Why:** EventBridge (formerly CloudWatch Events) uses the `events.amazonaws.com` service principal. The original policy allowed S3 to publish (useful for S3 event notifications, but not for EventBridge).

### Step 6: The complete fixed main.tf

```hcl
resource "aws_guardduty_detector" "main" {
  enable = true

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
  }

  finding_publishing_frequency = "FIFTEEN_MINUTES"
}

resource "aws_securityhub_account" "main" {}

resource "aws_securityhub_product_subscription" "guardduty" {
  product_arn = "arn:aws:securityhub:${data.aws_region.current.name}::product/aws/guardduty"
  depends_on  = [aws_securityhub_account.main]
}

resource "aws_cloudwatch_event_rule" "critical_findings" {
  name        = "security-hub-critical-findings"
  description = "Route critical Security Hub findings to SNS"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = ["CRITICAL", "HIGH"]
        }
      }
    }
  })
}

resource "aws_sns_topic_policy" "security_alerts" {
  arn = aws_sns_topic.security_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.security_alerts.arn
      }
    ]
  })
}
```

### Step 7: Validate

```bash
terraform validate
terraform plan
```

## Docker Lab vs Real Life

- **Multi-region:** In production, GuardDuty should be enabled in ALL regions, not just your primary. Attackers target unused regions where monitoring is often absent. Use AWS Organizations to enable GuardDuty across all accounts and regions.
- **Security Hub standards:** Enable CIS AWS Foundations Benchmark and AWS Foundational Security Best Practices standards in Security Hub. These provide automated compliance checks beyond GuardDuty findings.
- **Finding suppression:** In production, configure suppression rules for known false positives rather than ignoring all low-severity findings. Every finding should be reviewed at least once.
- **GuardDuty additional sources:** Consider enabling Malware Protection and RDS Protection data sources depending on your workload. EBS malware scanning catches threats that network-based detection misses.
- **Automated remediation:** Mature teams use EventBridge + Lambda for automated remediation (e.g., auto-isolating compromised instances, revoking leaked credentials). Start with alerting, then evolve to automation.
- **Inspector integration:** AWS Inspector provides vulnerability scanning for EC2 instances and container images. Subscribe Security Hub to Inspector alongside GuardDuty for a more complete security posture view.

## Key Concepts Learned

- **GuardDuty must be explicitly enabled** — creating a detector isn't enough. The `enable` flag controls whether it actively monitors.
- **Security Hub product subscriptions are required** — Security Hub doesn't auto-discover findings. You must subscribe to each product (GuardDuty, Inspector, Macie, etc.).
- **EventBridge severity filtering** — Security Hub findings have severity labels (CRITICAL, HIGH, MEDIUM, LOW, INFORMATIONAL). Filter appropriately for your alerting pipeline.
- **Service principals matter for SNS policies** — each AWS service uses its own principal (events.amazonaws.com, s3.amazonaws.com, etc.). Using the wrong one silently fails.
- **End-to-end verification** — security pipelines should be tested. Generate a sample finding with `aws guardduty create-sample-findings` to verify the entire chain works.

## Common Mistakes

- **Deploying GuardDuty but not enabling it** — terraform apply succeeds, but no monitoring happens. Always verify `enable = true`.
- **Forgetting product subscriptions** — Security Hub shows "No findings" and teams assume there are no issues, when actually the integration is broken.
- **Overly broad event patterns** — matching ALL findings floods the team with noise. Match on CRITICAL and HIGH for alerting, use dashboards for the rest.
- **Wrong SNS principal** — this is a common copy-paste error. Each AWS service has its own principal for resource policies.
- **Single-region deployment** — deploying security tools in only one region leaves others unmonitored. Attackers actively exploit this gap.
