Title: DNS Failover Not Working — Route 53 Configuration
Difficulty: ⭐⭐⭐ (Advanced)
Time: 20-25 minutes
Category: AWS / Route 53
Skills: Route 53, health checks, failover routing, DNS records, TTL

## Scenario

The Route 53 failover routing policy should switch traffic to the backup region when the primary is unhealthy, but failover isn't happening.

> **INCIDENT-AWS-008**: Primary region went down but Route 53 didn't failover to secondary. DNS still pointing to unhealthy primary. Customers experiencing full outage.

## How to Use This Lab

1. Review the Terraform files — find and fix the bugs
2. Run `terraform init && terraform plan` to see errors
3. Fix the issues in main.tf
4. Run `terraform plan` to verify no errors remain
5. (Optional) `terraform apply` if using a real AWS account or KodeKloud Playground

**Requires:** Terraform installed. AWS credentials for apply (optional — you can learn from plan alone).
