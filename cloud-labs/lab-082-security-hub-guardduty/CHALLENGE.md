Title: Security Findings Ignored — Security Hub & GuardDuty Misconfigured
Difficulty: ⭐⭐⭐ (Advanced)
Time: 20-25 minutes
Category: AWS / Security
Skills: Security Hub, GuardDuty, EventBridge, SNS, Terraform

## Scenario

Your company just passed an external audit — barely. The auditors flagged that AWS Security Hub and GuardDuty are deployed but not working effectively. Findings aren't being aggregated, GuardDuty coverage has gaps, and the alerting pipeline for critical findings is broken.

> **INCIDENT-SEC-001** — Priority: High
>
> The security team reports they haven't received any GuardDuty alerts in 3 weeks, despite known suspicious activity in the dev accounts. The Security Hub console shows "No findings" even though GuardDuty is supposedly enabled.
>
> Reporter: Security Team Lead
> Assigned to: You
> Environment: eu-west-2 (primary region)

## Your Task

You've been handed the ticket cold. The previous engineer who built this pipeline has left. All you have is the Terraform repo that deployed it.

Work out what's broken, fix it, and prove the pipeline works end-to-end.

## What You'll Practise

- Reading an incident ticket and translating symptoms into an investigation plan
- Tracing a multi-service AWS data flow (GuardDuty → Security Hub → EventBridge → SNS)
- Using AWS CLI to confirm resource state rather than trusting Terraform syntax
- Diagnosing silent misconfigurations that pass `terraform validate`
- Fixing EventBridge event patterns and SNS resource policies

## How to Approach This Lab

1. Read the incident ticket above carefully. Note the symptoms.
2. Deploy what's in the repo with `terraform init && terraform apply`.
3. Investigate. Don't jump into `main.tf` yet — confirm the fault with AWS CLI first.
4. Once you've identified *where* the pipeline is broken, *then* open `main.tf` to find *why*.
5. Fix, re-apply, and run `./validate.sh` to prove the pipeline is correctly configured.

The `SOLUTION.md` file walks through the full investigative thought process if you get stuck.

## Cleanup

When you're done, always run:

```bash
terraform destroy
```

Leaving GuardDuty and Security Hub enabled in an unused account will incur charges.

## Requirements

- Terraform installed (1.5+)
- AWS credentials configured (`aws configure`)
- Permissions: GuardDuty, Security Hub, EventBridge, SNS, IAM (read)
