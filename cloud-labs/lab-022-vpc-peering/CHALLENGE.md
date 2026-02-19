Title: Cross-VPC Traffic Blocked — VPC Peering Issues
Difficulty: ⭐⭐⭐ (Advanced)
Time: 20-25 minutes
Category: AWS / VPC Peering
Skills: VPC peering, route tables, security groups, CIDR overlap, DNS resolution

## Scenario

Two VPCs need to communicate via VPC peering but traffic isn't flowing despite the peering connection being active.

> **INCIDENT-AWS-013**: Application in VPC-A can't reach database in VPC-B. VPC peering connection shows 'active' but no traffic flowing. Both sides say the other is unreachable.

## How to Use This Lab

1. Review the Terraform files — find and fix the bugs
2. Run `terraform init && terraform plan` to see errors
3. Fix the issues in main.tf
4. Run `terraform plan` to verify no errors remain
5. (Optional) `terraform apply` if using a real AWS account or KodeKloud Playground

**Requires:** Terraform installed. AWS credentials for apply (optional — you can learn from plan alone).
