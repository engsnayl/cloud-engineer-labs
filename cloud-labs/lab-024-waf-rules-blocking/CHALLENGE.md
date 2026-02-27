Title: WAF Blocking Legitimate Traffic — Rule Debugging
Difficulty: ⭐⭐⭐ (Advanced)
Time: 20-25 minutes
Category: AWS / Security / WAF
Skills: AWS WAF, ALB, CloudWatch metrics, IP sets, rule priorities, Terraform

## Scenario

Your web application is behind an Application Load Balancer with AWS WAF attached. After a recent security hardening, legitimate users are getting 403 Forbidden errors. The security team applied new WAF rules but was too aggressive with the configuration.

> **INCIDENT-WAF-001**: Customer support reporting 60% increase in "Access Denied" complaints since Tuesday's WAF rule deployment. Application health checks are passing but real user traffic is being blocked.

## Objectives

1. Fix the WAF IP set so it doesn't block the office CIDR range
2. Fix the rate-limiting rule threshold so it doesn't block normal browsing
3. Fix the rule priorities so Allow rules are evaluated before blanket Deny rules
4. Fix the geo-restriction rule so it allows traffic from required countries
5. `terraform validate` must pass
6. `terraform plan` must complete without errors

## How to Use This Lab

1. Review the Terraform files — find and fix the bugs
2. Run `terraform init && terraform plan` to see errors
3. Fix the issues in main.tf
4. Run `terraform plan` to verify no errors remain
5. (Optional) `terraform apply` if using a real AWS account or KodeKloud Playground

**Requires:** Terraform installed. AWS credentials for apply (optional).

## Validation

Run `./validate.sh` or manually verify with `terraform plan`.
