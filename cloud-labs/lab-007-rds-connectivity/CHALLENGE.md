Title: Database Unreachable — RDS Security Group Issues
Difficulty: ⭐⭐ (Intermediate)
Time: 15-20 minutes
Category: AWS / RDS
Skills: RDS, security groups, subnet groups, VPC networking

## Scenario

The application EC2 instance can't connect to the RDS database. Both are in the same VPC but the security groups and subnet configuration are preventing connectivity.

> **INCIDENT-AWS-004**: Application can't connect to RDS MySQL. Connection timeout on port 3306. Both resources in same VPC. Security groups may be misconfigured.

## How to Use This Lab

1. Review the Terraform files — find and fix the bugs
2. Run `terraform init && terraform plan` to see errors
3. Fix the issues in main.tf
4. Run `terraform plan` to verify no errors remain
5. (Optional) `terraform apply` if using a real AWS account or KodeKloud Playground

**Requires:** Terraform installed. AWS credentials for apply (optional — you can learn from plan alone).

## Validation

Run `./validate.sh` or manually verify with `terraform plan` showing no unexpected changes.
