Title: WAF Blocking Legitimate Traffic — Rule Debugging
Difficulty: ⭐⭐⭐ (Advanced)
Time: 25-35 minutes
Category: AWS / Security / WAF
Skills: AWS WAF, CloudWatch metrics, IP sets, rule priorities, Terraform

## Scenario

Your web application sits behind AWS WAF. Over the weekend, the security team pushed a new WAF configuration as part of a broader hardening initiative. Since Monday morning the support inbox has been filling up with complaints.

> **INCIDENT-WAF-001**: Customer support reporting a 60% increase in "Access Denied" complaints since the weekend's WAF rule deployment. Application health checks are passing. Load balancer is healthy. Backend services are healthy. But real user traffic — office staff, UK customers, US customers — is getting 403 Forbidden.
>
> The security engineer who wrote the new rules is on annual leave. The on-call ticket is yours. Production traffic is being blocked right now.

## Objectives

1. Restore access for legitimate users
2. Ensure the WAF still blocks genuinely malicious traffic
3. `terraform validate` must pass
4. `terraform apply` must succeed against a real AWS account
5. `./validate.sh` must pass — this tests the deployed WAF configuration against expected real-world values, not just Terraform syntax

## How to Use This Lab

1. `terraform init`
2. `terraform apply` — deploy the (broken) WAF configuration to AWS
3. Investigate. Use the AWS CLI, CloudWatch metrics, and WAF sampled requests to understand what's actually happening in production.
4. Form hypotheses. Test them. Fix `main.tf`.
5. `terraform apply` again to push your fixes.
6. `./validate.sh` — confirm the deployed WAF matches expected real-world configuration.
7. `terraform destroy` when finished — **do not skip this, WAF resources incur cost**.

## What You'll Practise

- Reading and interpreting AWS WAF rule evaluation order
- Using AWS CLI to inspect live WAF state (`aws wafv2 get-web-acl`, `aws wafv2 get-ip-set`, `aws wafv2 get-sampled-requests`)
- Distinguishing between allow-lists and block-lists — and the consequences of mixing them
- Reasoning about rate-limit thresholds in the context of modern web traffic
- Identifying geo-restriction misconfigurations
- Treating WAF rule priority as a first-class design decision, not an afterthought

**Requires:** Terraform installed. AWS credentials with WAFv2 permissions in `eu-west-2`. Estimated cost if left running: ~$5/month for the Web ACL plus $1 per rule per month. **Destroy when done.**

## Validation

Run `./validate.sh` after `terraform apply`. The script queries live AWS resources and verifies the WAF configuration matches expected production values.
