# Lab 082 — Security Hub & GuardDuty Misconfigured

## TLDR (Plain English)

The security team's alerting pipeline is completely dead. When a GuardDuty finding happens, it's supposed to flow like this:

**GuardDuty detects something → Security Hub collects it → EventBridge spots the critical ones → SNS emails the team.**

None of that is happening. When you investigate, you find **five separate things** broken or weak across every stage of that pipeline:

1. **GuardDuty is deployed but switched off.** Someone set up the detector but never actually enabled it. It's just sitting there doing nothing.
2. **Even if GuardDuty were on, it wouldn't watch Kubernetes.** The EKS audit logs feature is also switched off.
3. **Security Hub's subscription to GuardDuty is implicit, not declared.** It happens to work today because of an AWS default — but your Terraform doesn't say so, which means your IaC isn't the source of truth for this pipeline.
4. **The EventBridge rule is filtering for the wrong thing.** It's only alerting on `INFORMATIONAL` (lowest priority) findings instead of `CRITICAL` and `HIGH`. So even if the pipeline worked, the team would only hear about trivial stuff.
5. **The SNS topic is guarded by the wrong doorman.** The policy says "I'll only accept messages from S3" — but EventBridge is the one trying to publish, so every message gets refused.

**Fix:** enable GuardDuty and its Kubernetes datasource, declare the GuardDuty subscription explicitly in Terraform, change the EventBridge filter to match `CRITICAL` and `HIGH`, and change the SNS policy to allow `events.amazonaws.com` instead of `s3.amazonaws.com`.

---

## Background: How the Pipeline Is Supposed to Work

Before investigating, understand the architecture — because the whole lab is about tracing a data flow to find where it breaks.

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐     ┌───────┐     ┌─────────┐
│  GuardDuty  │ ──► │ Security Hub │ ──► │  EventBridge │ ──► │  SNS  │ ──► │  Email  │
│  (detects)  │     │ (aggregates) │     │  (filters)   │     │(fans out)│    │  team   │
└─────────────┘     └──────────────┘     └──────────────┘     └───────┘     └─────────┘
```

**Each stage has a specific job:**

| Stage | Role | How it fails silently |
|---|---|---|
| **GuardDuty** | Watches CloudTrail, VPC Flow Logs, DNS logs, K8s audit logs, and more for threats | Can be deployed but disabled — looks like it's working in the console, but no findings are generated |
| **Security Hub** | Central dashboard that aggregates findings from multiple AWS security services | Only ingests findings from products it's explicitly subscribed to (some are subscribed by default, which can lull you into false confidence) |
| **EventBridge** | Rules-based router that matches incoming events against JSON patterns | Matches by severity label — a wrong label means the rule fires on the wrong events (or not at all) |
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

Before touching anything, read the repo.

```bash
cd ~/cloud-engineer-labs/cloud-labs/lab-082-security-hub-guardduty
ls -la
```

You see `main.tf`, `CHALLENGE.md`, `validate.sh`. No state file, no modules, no variables. Single-file Terraform deployment.

Take a quick look at `main.tf` — not to fix anything yet, just to understand what resources should exist:

```bash
grep "^resource" main.tf
```

You see roughly:

```
resource "aws_guardduty_detector" "main" {
resource "aws_securityhub_account" "main" {}
resource "aws_cloudwatch_event_rule" "critical_findings" {
resource "aws_cloudwatch_event_target" "sns" {
resource "aws_sns_topic" "security_alerts" {
resource "aws_sns_topic_policy" "security_alerts" {
resource "aws_sns_topic_subscription" "email" {
```

That confirms the pipeline architecture matches the diagram: GuardDuty → Security Hub → EventBridge → SNS → email.

**Now the important discipline:** don't read the resource bodies yet. The whole point is that you investigate the *running infrastructure* first, then go to the code once you know where it's broken. If you read the code first, you'll spot the bugs visually and learn nothing.

---

## Step 2 — Deploy and Confirm the Fault

You need to see the broken state with your own eyes.

```bash
terraform init
terraform apply -auto-approve
```

`terraform apply` succeeds with no errors, but you see a deprecation warning:

```
Warning: Argument is deprecated
  datasources is deprecated. Use aws_guardduty_detector_feature resources instead.
```

**File this away.** It's a warning, not an error. The lab still works, and you'll address it later (see Lab vs Real Life). For now, your mission is fixing the incident, not refactoring to the latest API.

**This is the first meaningful lesson:** `terraform apply` completing successfully tells you nothing about whether the pipeline actually works. Terraform confirms AWS accepted your config — it doesn't confirm the config does what you want. In fact, even with a warning, Terraform will still cheerfully apply it.

Now for the investigative mindset: don't jump into `main.tf` yet. **First, prove the fault exists by querying AWS directly.**

Why? Three reasons:

1. The ticket might be wrong. Tickets often misreport symptoms.
2. Something might have changed since the ticket was filed.
3. You need a baseline of "what's actually broken" to compare against after fixes.

---

## Step 3 — Is GuardDuty Actually Running?

The ticket says "GuardDuty is supposedly enabled." That's a hedge — someone deployed it, but is it actively doing its job?

First ask: does a detector exist at all?

```bash
aws guardduty list-detectors --region eu-west-2
```

**Command breakdown:**

| Component | What it does |
|---|---|
| `aws guardduty` | The AWS CLI service namespace for GuardDuty |
| `list-detectors` | Returns the IDs of all detectors in this region (typically one per region per account) |
| `--region eu-west-2` | Scope to your primary region; GuardDuty is regional, so each region is queried separately |

**Output:**

```json
{
    "DetectorIds": [
        "b6ced4ccccbd4f1e3b7622dd16a565ba"
    ]
}
```

Good — a detector exists. Save that ID, you'll need it:

```bash
DETECTOR_ID=$(aws guardduty list-detectors --region eu-west-2 --query 'DetectorIds[0]' --output text)
echo $DETECTOR_ID
```

**Command breakdown:**

| Component | What it does |
|---|---|
| `$(...)` | **Command substitution** — runs the inner command and captures its stdout |
| `DETECTOR_ID=` | **Variable assignment** — stores the captured text in a shell variable (no spaces around the `=`) |
| `--query 'DetectorIds[0]'` | JMESPath expression — pulls the first element of the `DetectorIds` array |
| `--output text` | Strips JSON formatting so you get just the raw ID string |

This is a pattern worth knowing — you'll use it in most AWS CLI investigations. The variable lives in your current shell session only (nothing on disk), and disappears when you close the terminal.

Now inspect the detector's actual runtime state:

```bash
aws guardduty get-detector --detector-id $DETECTOR_ID --region eu-west-2
```

**Tip:** the AWS CLI pipes long output to `less` by default, leaving you stuck at an `(END)` prompt. Press `q` to exit. To disable this behaviour, either add `--no-cli-pager` per-command or `export AWS_PAGER=""` in your shell.

**Output (abbreviated):**

```json
{
    "Status": "DISABLED",
    "DataSources": {
        "CloudTrail":  { "Status": "ENABLED" },
        "DNSLogs":     { "Status": "ENABLED" },
        "FlowLogs":    { "Status": "ENABLED" },
        "S3Logs":      { "Status": "ENABLED" },
        "Kubernetes":  { "AuditLogs": { "Status": "DISABLED" } }
    },
    "Features": [
        { "Name": "CLOUD_TRAIL",       "Status": "ENABLED"  },
        { "Name": "EKS_AUDIT_LOGS",    "Status": "DISABLED" },
        { "Name": "RUNTIME_MONITORING","Status": "DISABLED" },
        ...
    ]
}
```

**This is a finger-on-the-pulse moment. Two bugs visible in one command:**

1. **`Status: DISABLED`** at the top level — the detector exists but isn't actively monitoring. No findings will ever be generated. This single fact explains "no alerts in 3 weeks."
2. **`Kubernetes.AuditLogs.Status: DISABLED`** — even if you enable the detector, EKS threats won't be detected.

**Side note on the two parallel structures:** you'll notice the output contains both `DataSources` (older) and `Features` (newer) blocks describing the same things. GuardDuty is transitioning its API — the Terraform deprecation warning you saw earlier points at this. For now, both work, but the future belongs to the `Features` model.

**How would you have known to check this?** Because `list-detectors` only returns the ID, not the state. Seeing an ID doesn't mean the thing is working — it means it exists. The habit to learn:

> **Existence is not health.** Always check state, not just presence.

---

## Step 4 — Is Security Hub Receiving Findings?

Even with GuardDuty fixed, findings need to reach Security Hub. Security Hub is a separate service — it doesn't just magically know about GuardDuty.

First, confirm Security Hub is enabled:

```bash
aws securityhub describe-hub --region eu-west-2
```

**Output:**

```json
{
    "HubArn": "arn:aws:securityhub:eu-west-2:340752829546:hub/default",
    "SubscribedAt": "2026-04-20T06:35:09.811Z",
    "AutoEnableControls": true,
    "ControlFindingGenerator": "SECURITY_CONTROL"
}
```

Good — Security Hub is running. Now the key question: what products is it subscribed to?

```bash
aws securityhub list-enabled-products-for-import --region eu-west-2
```

**Output:**

```json
{
    "ProductSubscriptions": [
        "arn:aws:securityhub:...product-subscription/aws/access-analyzer",
        "arn:aws:securityhub:...product-subscription/aws/config",
        "arn:aws:securityhub:...product-subscription/aws/guardduty",
        "arn:aws:securityhub:...product-subscription/aws/inspector",
        "arn:aws:securityhub:...product-subscription/aws/macie",
        ...
    ]
}
```

**Wait — GuardDuty is already subscribed. So this is fine, right?**

This is where a junior engineer stops investigating and a senior one keeps going. Yes, the subscription exists in AWS. But look at `main.tf`:

```bash
grep "product_subscription" main.tf
```

Nothing. Zero references. The subscription isn't declared in Terraform.

**So what's keeping it alive?** An AWS default. When you enable Security Hub, AWS auto-subscribes you to a standard bundle (GuardDuty, Inspector, Config, Access Analyzer, Macie, and a few others). Convenient — but it's not under your control.

**Why this is a bug worth fixing:**

- If AWS changes the default bundle in a future release, your pipeline silently loses the subscription
- If someone runs `aws securityhub disable-import-findings-for-product` in the console, your Terraform won't detect or correct it
- Your IaC doesn't describe the actual desired state — it describes a subset, relying on AWS to fill in the rest

**The principle:** declarative infrastructure should be complete. If your IaC drifts out of sync with reality, `terraform plan` can't help — because Terraform doesn't know the subscription is supposed to exist.

> **Explicit is better than implicit.** Declare your dependencies in code, even when a default would give you the same result today. Defaults change. Your code shouldn't break when they do.

---

## Step 5 — Is the EventBridge Rule Routing the Right Events?

Next stage: EventBridge. Its job is to spot critical findings and forward them to SNS.

```bash
aws events describe-rule --name security-hub-critical-findings --region eu-west-2
```

**Output:**

```json
{
    "Name": "security-hub-critical-findings",
    "EventPattern": "{\"detail\":{\"findings\":{\"Severity\":{\"Label\":[\"INFORMATIONAL\"]}}},\"detail-type\":[\"Security Hub Findings - Imported\"],\"source\":[\"aws.securityhub\"]}",
    "State": "ENABLED"
}
```

That escaped-JSON-inside-JSON string is hideous to read. Use this pattern to decode it:

```bash
aws events describe-rule --name security-hub-critical-findings --region eu-west-2 \
  --query 'EventPattern' --output text | jq
```

**Command breakdown:**

| Component | What it does |
|---|---|
| `--query 'EventPattern'` | Pulls just the EventPattern field from the response |
| `--output text` | Strips the outer JSON quoting, giving us the raw inner string |
| `\| jq` | Parses that string as JSON and pretty-prints it |

Now you get something readable:

```json
{
  "source": ["aws.securityhub"],
  "detail-type": ["Security Hub Findings - Imported"],
  "detail": {
    "findings": {
      "Severity": {
        "Label": ["INFORMATIONAL"]
      }
    }
  }
}
```

**What this pattern says to EventBridge:** *"Fire only when you see a Security Hub finding whose severity label is exactly INFORMATIONAL."*

**What's wrong:** the security team wants alerts about *critical* problems. Security Hub's severity labels, from lowest to highest:

```
INFORMATIONAL → LOW → MEDIUM → HIGH → CRITICAL
```

`INFORMATIONAL` is the least important tier. An alerting rule that fires only on `INFORMATIONAL` findings and ignores `CRITICAL` is completely backwards. In three weeks of operation, any genuinely dangerous GuardDuty finding would have been labelled `HIGH` or `CRITICAL` — this rule would have **ignored every single one of them.**

**A note on EventBridge matching:** event pattern values must be arrays, and EventBridge treats the array as an OR match. Exact string matching only — there's no `>= HIGH` operator for the `Label` field. If you want `CRITICAL` and `HIGH`, you enumerate both.

---

## Step 6 — Can EventBridge Publish to SNS?

Last stage. Even if the rule matches the right events, it needs permission to publish to the SNS topic.

Find the topic:

```bash
TOPIC_ARN=$(aws sns list-topics --region eu-west-2 \
  --query "Topics[?contains(TopicArn, 'security-hub-critical-alerts')].TopicArn | [0]" \
  --output text)
echo $TOPIC_ARN
```

Inspect the resource policy:

```bash
aws sns get-topic-attributes \
  --topic-arn $TOPIC_ARN \
  --region eu-west-2 \
  --query 'Attributes.Policy' \
  --output text | jq
```

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
      "Resource": "arn:aws:sns:eu-west-2:340752829546:security-hub-critical-alerts"
    }
  ]
}
```

**Read it backwards** (IAM policies are easier that way):

| Reading backwards | Question answered | This policy's answer |
|---|---|---|
| `Resource` | What resource are we controlling? | The SNS topic `security-hub-critical-alerts` |
| `Action` | What actions are being governed? | `sns:Publish` |
| `Principal` | Who is allowed to perform the action? | The S3 service (`s3.amazonaws.com`) |
| `Effect` | Allowing or denying? | `Allow` |

**Plain English:** *"Allow S3 to publish messages to this SNS topic."*

EventBridge is the thing trying to publish — not S3. When EventBridge attempts `sns:Publish`, AWS checks the policy, doesn't see `events.amazonaws.com` in the allowed principals, and silently denies the call.

**Why silent?** AWS's default for resource policies is *deny everything except what's explicitly allowed.* A failed SNS publish from EventBridge produces:

- ❌ No error in your shell
- ❌ No entry in the Security Hub UI
- ❌ No email to anyone
- ✅ A CloudWatch metric: `FailedInvocations` on the rule (which nobody was watching)
- ✅ A CloudTrail entry: `Publish` with `errorCode: AuthorizationFailure`

In production, you'd set an alarm on `FailedInvocations > 0` for critical rules. Without it, the pipeline breaks invisibly — exactly what happened here for three weeks.

**Why does the wrong principal end up there?** It's a copy-paste trap. S3 event notifications use exactly this pattern:

```json
{
  "Principal": { "Service": "s3.amazonaws.com" },
  "Action": "sns:Publish",
  ...
}
```

An engineer writing an EventBridge-to-SNS policy can easily copy from an S3 example without updating the principal. The rest of the policy looks identical. One line wrong — massive consequence.

**The common AWS service principals worth memorising:**

| Service | Principal |
|---|---|
| EventBridge | `events.amazonaws.com` |
| Lambda | `lambda.amazonaws.com` |
| S3 | `s3.amazonaws.com` |
| SNS | `sns.amazonaws.com` |
| API Gateway | `apigateway.amazonaws.com` |
| CloudWatch Logs | `logs.amazonaws.com` |
| CloudTrail | `cloudtrail.amazonaws.com` |

---

## Step 7 — Diagnosis Summary

Before fixing anything, write down what you've found. This is what you'd put in the incident ticket:

> **Root cause analysis:**
>
> The security pipeline has five separate issues across all four stages of the alerting flow:
>
> 1. **GuardDuty detector is disabled** (`Status: DISABLED`). The detector exists but generates no findings.
> 2. **GuardDuty Kubernetes audit logs are disabled**. EKS threats would be invisible even with the detector on.
> 3. **Security Hub's GuardDuty subscription is implicit, not declared in IaC**. Works today by AWS default, but Terraform isn't the source of truth.
> 4. **EventBridge rule filters on INFORMATIONAL severity only**. Critical findings are ignored.
> 5. **SNS topic policy grants publish permission to S3, not EventBridge**. Matched findings can't be delivered.
>
> Fix: update `main.tf`, `terraform apply`, validate with AWS CLI calls matching the diagnostic ones.

Now — and only now — open `main.tf`.

---

## Step 8 — The Fixes, In Order

### 8.1 Enable the GuardDuty detector

```hcl
resource "aws_guardduty_detector" "main" {
  enable = true    # was: false
```

The `enable` argument is the runtime switch. `true` = actively monitoring, `false` = exists but dormant.

### 8.2 Enable Kubernetes audit log monitoring

```hcl
kubernetes {
  audit_logs {
    enable = true    # was: false
  }
}
```

GuardDuty's datasources are opt-in. Kubernetes audit logs detect EKS-related threats (suspicious kubectl API calls, privilege escalation attempts, compromised service accounts). Worth enabling whenever you run EKS workloads.

### 8.3 Declare the GuardDuty subscription explicitly

Add this new resource after `aws_securityhub_account.main`:

```hcl
resource "aws_securityhub_product_subscription" "guardduty" {
  product_arn = "arn:aws:securityhub:${data.aws_region.current.region}::product/aws/guardduty"
  depends_on  = [aws_securityhub_account.main]
}
```

**Resource breakdown:**

| Component | What it does |
|---|---|
| `aws_securityhub_product_subscription` | Resource type that tells Security Hub to ingest findings from a specific product |
| `product_arn` | AWS-published ARN for GuardDuty's integration — always `arn:aws:securityhub:<region>::product/aws/guardduty` |
| `${data.aws_region.current.region}` | Terraform interpolation — pulls the current AWS region from the data source (avoids hardcoding) |
| `depends_on` | Explicit ordering so Security Hub is created before the subscription tries to attach |

**Note:** older examples online use `data.aws_region.current.name`. The Terraform AWS provider has deprecated `.name` in favour of `.region`. Use `.region` for new code — you'll see a warning otherwise.

**What this achieves:** since AWS was already auto-subscribed, `terraform apply` will be a no-op from AWS's perspective — but now Terraform knows about the subscription. From this point on:

- If someone disables the subscription in the console, `terraform plan` will show drift
- `terraform destroy` properly tears it down (before, it was orphaned)
- A future AWS default change won't break your pipeline

### 8.4 Fix the EventBridge severity filter

```hcl
Label = [
  "CRITICAL",
  "HIGH"
]
# was: "INFORMATIONAL"
```

The `Label` field takes an array — EventBridge treats it as OR-matching. For alerting, `CRITICAL` and `HIGH` are the canonical pair: serious enough to page someone. `MEDIUM` and below typically go to a dashboard, not an alert pipeline.

### 8.5 Fix the SNS topic policy principal

```hcl
Principal = {
  Service = "events.amazonaws.com"    # was: s3.amazonaws.com
}
```

Same structure, correct principal. `events.amazonaws.com` is what EventBridge uses when publishing to SNS.

---

## Step 9 — Apply and Verify

```bash
terraform apply -auto-approve
```

Expected: 1 resource to add (the new subscription), 3 to change (detector, event rule, SNS policy), 0 to destroy.

Now — and this is important — re-run the **same investigative commands** to prove each fix landed. Observation-based verification, not `terraform plan`:

```bash
# Bugs #1 & #2 fixed?
aws guardduty get-detector --detector-id $DETECTOR_ID --region eu-west-2 \
  --query '{DetectorStatus: Status, K8sAudit: DataSources.Kubernetes.AuditLogs.Status}'
```
Expected: both `ENABLED`.

```bash
# Bug #3 now declared?
grep "aws_securityhub_product_subscription" main.tf
```
Expected: one match.

```bash
# Bug #4 fixed?
aws events describe-rule --name security-hub-critical-findings --region eu-west-2 \
  --query 'EventPattern' --output text | jq '.detail.findings.Severity.Label'
```
Expected: `["CRITICAL", "HIGH"]`.

```bash
# Bug #5 fixed?
aws sns get-topic-attributes --topic-arn $TOPIC_ARN --region eu-west-2 \
  --query 'Attributes.Policy' --output text | jq '.Statement[0].Principal'
```
Expected: `{ "Service": "events.amazonaws.com" }`.

Then the full validation script:

```bash
./validate.sh
```

All 12 checks should pass green.

**End-to-end test (optional but recommended):**

```bash
aws guardduty create-sample-findings \
  --detector-id $DETECTOR_ID \
  --finding-types Backdoor:EC2/C\&CActivity.B!DNS \
  --region eu-west-2
```

Within 1-2 minutes, a real finding flows through the pipeline. If you've updated the email subscription to your own address (the default is `security-team@example.com`, which won't receive anything real), you'll see it arrive. That's the true end-to-end proof.

---

## Step 10 — Reset (Destroy)

Always tear down. GuardDuty and Security Hub both incur charges per finding analysed and per account-month enabled.

```bash
terraform destroy -auto-approve
```

**IMPORTANT:** `terraform destroy` is the happy path for cleanup. It removes every resource this config created — including the `aws_securityhub_product_subscription` you just added, which is why declaring it in IaC matters. Don't rely on manual console cleanup; it's easy to miss a detector and get billed for months.

After destroy, revert your local `main.tf` to the broken state so the lab is repeatable:

```bash
git checkout main.tf
```

---

## Lab vs Real Life

What this lab teaches vs what you'd do in production:

| Topic | This Lab | Production Reality |
|---|---|---|
| **Regions** | Single region (eu-west-2) | GuardDuty enabled in **every** region, not just your primary. Attackers deliberately exploit unused regions because monitoring is often absent. Use AWS Organizations + delegated admin to roll out across all regions, all accounts. |
| **Security Hub standards** | Basic aggregation only | Enable CIS AWS Foundations Benchmark and AWS Foundational Security Best Practices. Continuous compliance checks beyond GuardDuty's threat detection. |
| **Severity tiering** | Single pipe: `CRITICAL`+`HIGH` to SNS | Production pipelines tier: `CRITICAL` pages on-call immediately, `HIGH` → Slack, `MEDIUM` → daily digest, `LOW`/`INFORMATIONAL` → dashboard only. |
| **The `datasources` deprecation warning** | Left in place (note it, don't fix it during the incident) | File a ticket to migrate to `aws_guardduty_detector_feature` resources. Don't let warnings rot into errors when AWS finally removes the old API. An engineer who ignores all warnings is sloppy; one who treats every warning as urgent is unproductive — the judgment call is what separates mid from senior. |
| **Suppression** | Not addressed | Known false positives should have explicit suppression rules, not be silently ignored. Every finding reviewed at least once. |
| **Additional data sources** | CloudTrail + K8s only | Consider EBS Malware Protection, RDS Protection, Lambda Protection, Runtime Monitoring. Each catches threats invisible to network-based detection. |
| **Automated remediation** | Alerting only | Mature teams add Lambda as additional EventBridge target — auto-isolate compromised instances, auto-revoke leaked credentials, auto-quarantine malicious IPs. |
| **Inspector integration** | Not included | Add AWS Inspector for EC2 and container image vulnerability scanning. Subscribe Security Hub to Inspector alongside GuardDuty for fuller posture. |
| **Pipeline testing** | `create-sample-findings` once | Production teams run regular fire drills — scheduled sample findings to prove the pipeline still works. Pipelines that aren't tested always rot. |
| **Alarm on failure** | Not configured | `CloudWatch alarm on rule.FailedInvocations > 0` — catches the exact silent failure mode this lab demonstrates. |

---

## Key Concepts Learned

- **Existence is not health.** A resource being deployed doesn't mean it's operational. Always check runtime state (`Status: ENABLED`), not just presence.
- **Explicit is better than implicit.** Declare your dependencies in IaC, even when a default would give you the same result today. Defaults change.
- **`terraform apply` is not functional validation.** It confirms AWS accepted the config, not that the config does what you want. Even with deprecation warnings, apply succeeds.
- **EventBridge matches on exact strings.** Wrong severity label = wrong events fired (or no events). No partial matching for string fields.
- **Service principals matter.** Every AWS service uses its own principal for resource policies. Wrong principal = silent denial. Memorise the common ones.
- **Silent failures are the dangerous ones.** A pipeline that logs errors is easy to fix. A pipeline that silently drops messages is invisible until an auditor asks "when was your last alert?"
- **Observe, then diagnose.** For multi-service pipelines, investigate stage by stage with AWS CLI calls — don't read `main.tf` first. The runbook might be wrong. AWS is the source of truth.
- **Verify the fix with the same commands you used to find the bug.** If `get-detector` showed `Status: DISABLED` before, re-run it after the fix. Observation-based verification beats "terraform plan looks clean."
- **Validation scripts need testing too.** A validate script with a wrong topic name (like the one this lab originally shipped with) is as dangerous as no validation — false failures erode trust in tooling.

---

## Common Mistakes

- **Deploying GuardDuty without enabling it** — `terraform apply` succeeds, no monitoring happens.
- **Trusting AWS defaults** — your IaC should declare everything it depends on, even free "bonus" subscriptions. Defaults change without notice.
- **Reading config before observing reality** — you'll spot bugs by pattern-matching instead of learning the diagnostic discipline.
- **Ignoring deprecation warnings** — they're not urgent today, but they rot into breakage when AWS removes the old API. File a ticket; don't ignore.
- **Wrong service principal in resource policies** — silent denial. Test by actually publishing something, not just by deploying.
- **Overly broad event patterns** — matching all findings floods the team with noise. Tier your alerts by severity.
- **Single-region deployment** — attackers actively probe unused regions.
- **Trusting `terraform apply` as validation** — apply succeeding is a syntax check, not a functional one.

---

## Pi / AWS Environment Notes

- All AWS investigation calls in this lab are read-only metadata operations (`list-*`, `get-*`, `describe-*`) — no cost impact beyond standard API request pricing (effectively zero for this volume)
- GuardDuty charges per event analysed (CloudTrail events, VPC Flow Logs, DNS queries) — destroy after the lab to avoid ongoing charges
- Security Hub charges per finding ingested and per compliance check — destroy after the lab
- SNS topic with an unverified email subscription (`security-team@example.com`) won't actually send anything; to test end-to-end, update the subscription to your own email before running `create-sample-findings`
- The Terraform deprecation warning for `datasources` is expected and is addressed in the Lab vs Real Life section — don't let it distract you from the core investigation
