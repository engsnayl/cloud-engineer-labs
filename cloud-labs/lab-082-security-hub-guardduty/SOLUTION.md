# Lab 082 — Security Hub & GuardDuty Misconfigured

## TLDR (Plain English)

The security team's alerting pipeline is completely dead. When a GuardDuty finding happens, it's supposed to flow like this:

**GuardDuty detects something → Security Hub collects it → EventBridge spots the critical ones → SNS emails the team.**

None of that is happening. When you investigate, you find five separate things broken across every stage of that pipeline:

1. **GuardDuty is deployed but switched off.** Someone set up the detector but never actually enabled it. It's just sitting there doing nothing.
2. **Even if GuardDuty were on, it wouldn't watch Kubernetes.** The EKS monitoring datasource is also switched off.
3. **Security Hub isn't listening to GuardDuty.** The two services don't automatically talk to each other — you have to explicitly tell Security Hub "please ingest GuardDuty findings." Nobody did.
4. **The EventBridge rule is filtering for the wrong thing.** It's only alerting on `INFORMATIONAL` (lowest priority) findings instead of `CRITICAL` and `HIGH`. So even if the pipeline worked, the team would only hear about trivial stuff.
5. **The SNS topic is guarded by the wrong doorman.** The policy says "I'll only accept messages from S3" — but EventBridge is the one trying to publish, so every message gets refused.

**Fix:** enable GuardDuty and its Kubernetes datasource, subscribe Security Hub to GuardDuty findings, change the EventBridge filter to match `CRITICAL` and `HIGH`, and change the SNS policy to allow `events.amazonaws.com` instead of `s3.amazonaws.com`.

---

## Background: How the Pipeline Is Supposed to Work

Before we investigate, understand the architecture, because the whole lab is about tracing a data flow to find where it breaks.

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐     ┌───────┐     ┌─────────┐
│  GuardDuty  │ ──► │ Security Hub │ ──► │  EventBridge │ ──► │  SNS  │ ──► │  Email  │
│  (detects)  │     │ (aggregates) │     │  (filters)   │     │(fans out)│    │  team   │
└─────────────┘     └──────────────┘     └──────────────┘     └───────┘     └─────────┘
```

**Each stage has a specific job:**

| Stage | Role | How it fails silently |
|---|---|---|
| **GuardDuty** | Watches CloudTrail, VPC Flow Logs, DNS logs, K8s audit logs for threats | Can be deployed but disabled — looks like it's working in the console, but no findings generated |
| **Security Hub** | Central dashboard that aggregates findings from multiple AWS security services | Doesn't automatically ingest from GuardDuty — requires an explicit product subscription |
| **EventBridge** | Rules-based router that matches incoming events against patterns | Matches by severity label — a wrong label means the rule fires on the wrong events (or not at all) |
| **SNS** | Pub/sub messaging — takes a message and fans it out to subscribers | Resource policy controls who can publish — wrong service principal means all publish attempts are silently denied |

Every stage has a "looks fine but isn't" failure mode. That's what makes this lab realistic — in production, these pipelines break silently for weeks before anyone notices.

---

## You Arrive at the Scene

Monday morning. Coffee in hand. You open your ticket queue.

> **INCIDENT-SEC-001** — Priority: High
>
> The security team reports they haven't received any GuardDuty alerts in 3 weeks, despite known suspicious activity in the dev accounts. The Security Hub console shows "No findings" even though GuardDuty is supposedly enabled.

The previous engineer who built this pipeline has left. All you have is the Terraform repo.

Three weeks of no alerts is bad. Your job is to work out why, fix it, and prove the fix works end-to-end.

---

## Step 1 — Understand What You're Dealing With

Before you touch anything, read the repo.

```bash
cd ~/cloud-engineer-labs/cloud-labs/lab-082-security-hub-guardduty
ls -la
```

You see `main.tf`, `CHALLENGE.md`, `validate.sh`. No `variables.tf`, no modules, no state file. This is a single-file Terraform deployment.

Take a quick look at `main.tf` — not to fix anything yet, just to understand what resources *should* exist:

```bash
grep "^resource" main.tf
```

You should see roughly:

```
resource "aws_guardduty_detector" "main" {
resource "aws_securityhub_account" "main" {}
resource "aws_cloudwatch_event_rule" "critical_findings" {
resource "aws_cloudwatch_event_target" "sns" {
resource "aws_sns_topic" "security_alerts" {
resource "aws_sns_topic_policy" "security_alerts" {
resource "aws_sns_topic_subscription" "email" {
```

That tells you the pipeline architecture matches the diagram: GuardDuty → Security Hub → EventBridge → SNS → email.

**Now the important discipline:** don't read the resource bodies yet. The whole point of this lab is that you investigate the *running infrastructure* first, then go to the code once you know where it's broken. If you read the code first, you'll spot the bugs visually and learn nothing.

---

## Step 2 — Deploy and Confirm the Fault

You need to see the broken state with your own eyes. Deploy whatever's in the repo:

```bash
terraform init
terraform apply -auto-approve
```

`terraform apply` succeeds with no errors. Every bug in this lab produces valid Terraform. That's the first meaningful lesson: **`terraform apply` completing successfully tells you nothing about whether the pipeline actually works.** Terraform confirms AWS accepted your config — it doesn't confirm the config does what you want.

Now for the investigative mindset: don't jump into `main.tf` yet. **First, prove the fault exists by querying AWS directly.**

Why? Three reasons:

1. The ticket might be wrong. Tickets often misreport symptoms.
2. Something might have changed since the ticket was filed.
3. You need a baseline of "what's actually broken" to compare against once you've made fixes.

---

## Step 3 — Is GuardDuty Actually Running?

The ticket says "GuardDuty is supposedly enabled." That's a hedge — someone deployed it, but is it actually doing its job?

The first CLI call asks: does a detector exist at all?

```bash
aws guardduty list-detectors --region eu-west-2
```

**Command breakdown:**

| Component | What it does |
|---|---|
| `aws guardduty` | The AWS CLI service namespace for GuardDuty |
| `list-detectors` | Returns the IDs of all detectors in this region (there's typically one per region per account) |
| `--region eu-west-2` | Scope to your primary region; GuardDuty is regional, so you query each region separately |

**Output:**

```json
{
    "DetectorIds": [
        "abc123detectorid456"
    ]
}
```

Good — a detector exists. So the previous engineer did create one. Save that ID; you'll need it.

```bash
DETECTOR_ID=$(aws guardduty list-detectors --region eu-west-2 --query 'DetectorIds[0]' --output text)
echo $DETECTOR_ID
```

**Command breakdown:**

| Component | What it does |
|---|---|
| `$(...)` | Bash command substitution — runs the command and assigns its output to the variable |
| `--query 'DetectorIds[0]'` | JMESPath expression — pulls the first element of the `DetectorIds` array |
| `--output text` | Strips JSON formatting so you get just the raw ID string |

Now inspect the detector's actual runtime state:

```bash
aws guardduty get-detector --detector-id $DETECTOR_ID --region eu-west-2
```

**Output (the critical bit):**

```json
{
    "Status": "DISABLED",
    "ServiceRole": "...",
    "DataSources": {
        "CloudTrail": { "Status": "ENABLED" },
        "DNSLogs": { "Status": "ENABLED" },
        "FlowLogs": { "Status": "ENABLED" },
        "S3Logs": { "Status": "ENABLED" },
        "Kubernetes": {
            "AuditLogs": { "Status": "DISABLED" }
        }
    },
    "FindingPublishingFrequency": "FIFTEEN_MINUTES"
}
```

**This is a finger-on-the-pulse moment.** Two problems visible in one command:

1. **`Status: DISABLED`** — the detector exists but isn't actively monitoring. No findings will ever be generated. This single fact explains "no alerts in 3 weeks."
2. **`Kubernetes.AuditLogs.Status: DISABLED`** — even if you enable the detector, EKS threats won't be detected.

**How would you have known to check this?** Because `list-detectors` only returns the ID, not the state. Seeing an ID doesn't mean the thing is working — it means it exists. The habit to learn: *existence is not health*. Always check state, not just presence.

---

## Step 4 — Is Security Hub Receiving Findings?

Even when you fix GuardDuty, findings need to reach Security Hub. Security Hub is a separate service — it doesn't auto-subscribe to anything.

First, confirm Security Hub is at least enabled in this region:

```bash
aws securityhub describe-hub --region eu-west-2
```

If it returns an ARN, Security Hub is on. Now the key question — what products is it actually subscribed to?

```bash
aws securityhub list-enabled-products-for-import --region eu-west-2
```

**Command breakdown:**

| Component | What it does |
|---|---|
| `list-enabled-products-for-import` | Returns the ARNs of products currently feeding findings into Security Hub |

**Output:**

```json
{
    "ProductSubscriptions": []
}
```

**Empty.** Security Hub isn't subscribed to anything. Not GuardDuty, not Inspector, not Macie — nothing.

**Why does this matter?** A newcomer to AWS security tooling might assume "Security Hub is a dashboard, so of course it shows everything." It doesn't. Security Hub is more like a pub/sub topic — each security service is a publisher, and Security Hub only receives from publishers you've explicitly subscribed it to.

**How would you know to check this?** Because the ticket said "Security Hub console shows No findings." That symptom has two possible causes:

1. GuardDuty isn't generating findings (you've already confirmed this is true — it's disabled).
2. Security Hub isn't subscribed to receive them.

Both are separately true here. Fixing one won't fix the other.

---

## Step 5 — Is the EventBridge Rule Routing the Right Events?

Next stage in the pipeline: EventBridge. Its job is to spot critical findings and forward them to SNS.

First, does the rule exist?

```bash
aws events list-rules --region eu-west-2 --query "Rules[?contains(Name, 'security')]"
```

**Command breakdown:**

| Component | What it does |
|---|---|
| `aws events list-rules` | Lists all EventBridge rules in this region |
| `--query "Rules[?contains(Name, 'security')]"` | JMESPath filter — only return rules whose name contains "security" |

You should see `security-hub-critical-findings`. Good — the rule exists. Now inspect its event pattern:

```bash
aws events describe-rule --name security-hub-critical-findings --region eu-west-2
```

**Output (the important part):**

```json
{
    "EventPattern": "{\"source\":[\"aws.securityhub\"],\"detail-type\":[\"Security Hub Findings - Imported\"],\"detail\":{\"findings\":{\"Severity\":{\"Label\":[\"INFORMATIONAL\"]}}}}",
    "State": "ENABLED"
}
```

Read the event pattern carefully. It's matching on `Severity.Label = ["INFORMATIONAL"]`.

**Is that right?** The ticket asks for *critical* findings to reach the team. Security Hub's severity labels, from lowest to highest, are:

```
INFORMATIONAL → LOW → MEDIUM → HIGH → CRITICAL
```

`INFORMATIONAL` is the least important tier. An alerting rule that fires only on `INFORMATIONAL` findings and ignores `CRITICAL` is backwards.

**How would you know what labels are available?** Two ways:
1. AWS Security Hub documentation lists them.
2. `aws securityhub get-findings --max-results 1` on an active account shows the `Severity.Label` field in real findings.

For this lab, the fix is to replace `INFORMATIONAL` with `["CRITICAL", "HIGH"]` — the two tiers that warrant waking the security team up.

---

## Step 6 — Can EventBridge Publish to SNS?

Last stage. Even if the rule matches the right events, it needs permission to publish to the SNS topic.

Find the topic ARN:

```bash
aws sns list-topics --region eu-west-2 --query "Topics[?contains(TopicArn, 'security-hub-critical-alerts')]"
```

You'll get the ARN. Now inspect its resource policy:

```bash
aws sns get-topic-attributes \
  --topic-arn arn:aws:sns:eu-west-2:123456789012:security-hub-critical-alerts \
  --region eu-west-2 \
  --query 'Attributes.Policy' \
  --output text | jq
```

**Command breakdown:**

| Component | What it does |
|---|---|
| `aws sns get-topic-attributes` | Returns all metadata about the topic, including the access policy |
| `--query 'Attributes.Policy'` | JMESPath pulls just the policy JSON string |
| `--output text` | Strips the outer JSON wrapper so we get raw policy JSON |
| `| jq` | Pretty-prints the JSON (requires `jq` installed — drop it if you don't have it) |

**Output:**

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "s3.amazonaws.com"
            },
            "Action": "sns:Publish",
            "Resource": "arn:aws:sns:eu-west-2:123456789012:security-hub-critical-alerts"
        }
    ]
}
```

Look at the `Principal`. The policy only allows `s3.amazonaws.com` to publish. But EventBridge's service principal is `events.amazonaws.com`. When EventBridge tries to forward a finding, SNS silently denies it.

**How would you know EventBridge's principal is `events.amazonaws.com`?** Every AWS service that publishes to resource policies has its own principal. The pattern is usually `<service>.amazonaws.com`. If you're unsure, the fastest check is the AWS documentation page for EventBridge → "Using resource-based policies" → the example shows the principal. You'll memorise a handful (lambda, events, s3, sns, apigateway) within a few weeks of using them.

**Why does this fail silently?** Because SNS's default behaviour when a publisher lacks permission is to reject the message without throwing a noisy error. EventBridge logs it as a failed invocation, but unless you're watching the "FailedInvocations" CloudWatch metric for the rule, you'll never see it. Another realistic production failure mode.

---

## Step 7 — The Diagnosis Summary

Before you fix anything, write down what you've found. This is what you'd put in the incident ticket:

> Root cause analysis:
>
> The security pipeline has five separate misconfigurations across all four stages of the alerting flow:
>
> 1. **GuardDuty detector is disabled** (Status: DISABLED). The detector exists but generates no findings.
> 2. **GuardDuty Kubernetes audit logs are disabled**. EKS threats would be invisible even with the detector on.
> 3. **Security Hub has no product subscriptions**. Even if GuardDuty produced findings, Security Hub wouldn't ingest them.
> 4. **EventBridge rule filters on INFORMATIONAL severity only**. Critical findings would be ignored.
> 5. **SNS topic policy grants publish permission to S3, not EventBridge**. Matched findings couldn't be delivered.
>
> Fix: update `main.tf`, `terraform apply`, validate with AWS CLI.

Now — and only now — you open `main.tf`.

---

## Step 8 — The Fixes, In Order

You've traced the pipeline from source to destination. Now fix each stage.

### 8.1 Enable the GuardDuty detector

**Find in `main.tf`:**

```hcl
resource "aws_guardduty_detector" "main" {
  enable = false
```

**Change to:**

```hcl
resource "aws_guardduty_detector" "main" {
  enable = true
```

Single-value change. The `enable` argument is the runtime switch for the detector — `true` means it's actively monitoring, `false` means it exists but is dormant.

### 8.2 Enable Kubernetes audit log monitoring

**Find:**

```hcl
kubernetes {
  audit_logs {
    enable = false
  }
}
```

**Change to:**

```hcl
kubernetes {
  audit_logs {
    enable = true
  }
}
```

GuardDuty's datasources are opt-in. Each one has its own `enable` flag. Kubernetes audit logs are specifically for detecting EKS-related threats (suspicious kubectl API calls, privilege escalation attempts, compromised service accounts). Worth enabling whenever you run EKS workloads.

### 8.3 Subscribe Security Hub to GuardDuty findings

This is an *additional resource* — not a tweak to an existing one.

**Add to `main.tf`:**

```hcl
resource "aws_securityhub_product_subscription" "guardduty" {
  product_arn = "arn:aws:securityhub:${data.aws_region.current.name}::product/aws/guardduty"
  depends_on  = [aws_securityhub_account.main]
}
```

**Resource breakdown:**

| Component | What it does |
|---|---|
| `aws_securityhub_product_subscription` | The resource type that tells Security Hub to ingest findings from a specific product |
| `product_arn` | The AWS-published ARN for GuardDuty's integration — always has the format `arn:aws:securityhub:<region>::product/aws/guardduty` |
| `${data.aws_region.current.name}` | Terraform interpolation — pulls the current AWS region from the data source (avoids hardcoding `eu-west-2` in multiple places) |
| `depends_on` | Explicit dependency so Terraform creates the Security Hub account resource first; without this, the subscription might try to create before Security Hub is enabled |

### 8.4 Fix the EventBridge severity filter

**Find:**

```hcl
Label = [
  "INFORMATIONAL"
]
```

**Change to:**

```hcl
Label = [
  "CRITICAL",
  "HIGH"
]
```

The `Label` field takes an array, so you can include multiple severity tiers. For an alerting rule, `CRITICAL` and `HIGH` are the usual pair — they represent findings serious enough to warrant immediate human attention. `MEDIUM` and below typically go into a dashboard for review, not an alert pipeline.

### 8.5 Fix the SNS topic policy principal

**Find:**

```hcl
Principal = {
  Service = "s3.amazonaws.com"
}
```

**Change to:**

```hcl
Principal = {
  Service = "events.amazonaws.com"
}
```

Same structure, different service principal. `events.amazonaws.com` is what EventBridge uses when publishing to SNS. S3 uses `s3.amazonaws.com` when it's sending its own event notifications — which is likely why someone copy-pasted it from a different lab or stack.

---

## Step 9 — Apply and Verify

Apply the fixes:

```bash
terraform apply -auto-approve
```

You'll see updates to the detector, the event rule, the SNS policy, and a *create* for the new product subscription.

Now re-run the same AWS CLI investigation to prove each stage is fixed:

```bash
# 1. GuardDuty enabled?
aws guardduty get-detector --detector-id $DETECTOR_ID --region eu-west-2 \
  --query '{Status: Status, K8sAudit: DataSources.Kubernetes.AuditLogs.Status}'
```

Expected: `{"Status": "ENABLED", "K8sAudit": "ENABLED"}`

```bash
# 2. Security Hub subscribed to GuardDuty?
aws securityhub list-enabled-products-for-import --region eu-west-2
```

Expected: a `ProductSubscriptions` array containing a GuardDuty ARN.

```bash
# 3. EventBridge rule matches CRITICAL and HIGH?
aws events describe-rule --name security-hub-critical-findings --region eu-west-2 \
  --query 'EventPattern'
```

Expected: output contains `"CRITICAL"` and `"HIGH"`, no `"INFORMATIONAL"`.

```bash
# 4. SNS policy allows events.amazonaws.com?
aws sns get-topic-attributes \
  --topic-arn <your-topic-arn> \
  --region eu-west-2 \
  --query 'Attributes.Policy' --output text | grep events.amazonaws.com
```

Expected: a match on the grep.

Finally, prove the pipeline works end-to-end by generating a sample finding:

```bash
aws guardduty create-sample-findings \
  --detector-id $DETECTOR_ID \
  --finding-types Backdoor:EC2/C\&CActivity.B!DNS \
  --region eu-west-2
```

Within a minute or two, the security team should receive an email. (Or the subscribed email address, anyway — `security-team@example.com` won't actually receive anything. For a real test, update the subscription to your own email before running this.)

Then run the validate script:

```bash
./validate.sh
```

All checks should pass.

---

## Step 10 — Reset (Destroy)

Always tear down. GuardDuty and Security Hub both incur charges per finding analysed and per account-month enabled.

```bash
terraform destroy -auto-approve
```

**IMPORTANT:** `terraform destroy` is the happy path for cleanup. It removes every resource this config created. Don't rely on manual console cleanup — it's easy to miss a detector and get billed for months.

---

## Lab vs Real Life

What this lab teaches vs what you'd do in production:

| Topic | This Lab | Production Reality |
|---|---|---|
| **Regions** | Single region (eu-west-2) | GuardDuty must be enabled in **every** region, not just your primary. Attackers deliberately exploit unused regions because monitoring is often absent. Use AWS Organizations + delegated admin to roll out GuardDuty across all regions, all accounts, in one move. |
| **Security Hub standards** | Just basic aggregation | Enable CIS AWS Foundations Benchmark and AWS Foundational Security Best Practices. These run continuous compliance checks beyond GuardDuty's threat detection. |
| **Severity filter** | `CRITICAL` + `HIGH` to SNS | Production pipelines tier their alerting: `CRITICAL` pages on-call immediately, `HIGH` goes to Slack, `MEDIUM` goes to a daily digest, `LOW`/`INFORMATIONAL` are dashboard-only. |
| **Suppression** | Not addressed | Known false positives should have explicit suppression rules, not be silently ignored. Every finding should be reviewed at least once. |
| **Additional data sources** | CloudTrail + K8s only | Consider Malware Protection (EBS snapshot scanning), RDS Protection, Lambda Protection. Each catches threats invisible to network-based detection. |
| **Automated remediation** | Alerting only | Mature teams add Lambda functions as additional EventBridge targets — auto-isolate compromised instances, auto-revoke leaked credentials, auto-quarantine malicious IPs. |
| **Inspector integration** | Not included | Add AWS Inspector for EC2 and container image vulnerability scanning. Subscribe Security Hub to Inspector alongside GuardDuty for a fuller posture view. |
| **Testing the pipeline** | `create-sample-findings` | Production teams run regular fire drills — deliberate sample findings on a schedule to prove the pipeline still works. Pipelines that aren't tested always rot. |

---

## Key Concepts Learned

- **Existence is not health.** A resource being deployed doesn't mean it's operational. Always check the runtime state (`Status: ENABLED`), not just presence.
- **Security Hub product subscriptions are required.** Security Hub doesn't auto-discover anything. Every security service you want it to ingest from needs an explicit `aws_securityhub_product_subscription`.
- **EventBridge matches on exact strings.** Getting the severity label wrong means the rule either fires on the wrong events or doesn't fire at all. There's no partial matching, no fuzziness.
- **Service principals matter.** Every AWS service uses its own principal for resource policies. Wrong principal = silent denial. Common ones: `events.amazonaws.com`, `lambda.amazonaws.com`, `s3.amazonaws.com`, `sns.amazonaws.com`.
- **`terraform validate` is a weak signal.** It catches syntax errors, not semantic ones. `enable = false` is valid HCL. Always validate against actual AWS state, not just Terraform syntax.
- **Silent failures are the dangerous ones.** A pipeline that logs errors is easy to fix. A pipeline that silently drops messages is invisible until an auditor asks "when was your last alert?"
- **Trace the data flow.** For any multi-service pipeline, investigate stage by stage: source → aggregation → routing → delivery. Don't guess at the bug — prove where it is.

---

## Common Mistakes

- **Deploying GuardDuty without enabling it** — `terraform apply` succeeds, but no monitoring happens. Always verify `enable = true`.
- **Forgetting product subscriptions** — Security Hub shows "No findings" and teams assume there are no issues, when actually the integration is broken. This is one of the most common causes of "silent security."
- **Overly broad event patterns** — matching ALL findings floods the team with noise. Match on `CRITICAL` and `HIGH` for alerting, use dashboards for the rest.
- **Wrong service principal in resource policies** — silent denial. Test by actually publishing something, not just by deploying.
- **Single-region deployment** — deploying security tools in only one region leaves others unmonitored. Attackers actively probe for this gap.
- **Trusting `terraform apply` as validation** — apply succeeding is a syntax check, not a functional check. Always test the behaviour.
