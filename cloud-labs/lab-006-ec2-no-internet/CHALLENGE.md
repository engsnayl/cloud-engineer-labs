Title: EC2 Can't Reach Internet — VPC Networking
Difficulty: ⭐⭐ (Intermediate)
Time: 15-20 minutes
Category: AWS / VPC
Skills: VPC, subnets, route tables, NAT Gateway, Internet Gateway

## Scenario

An EC2 instance in a private subnet can't reach the internet for package updates. It needs outbound internet access via a NAT Gateway but the routing isn't working.

> **INCIDENT-AWS-003**: EC2 instance can't reach package repositories or external APIs. Instance is in a private subnet. NAT Gateway exists but traffic isn't routing through it.

## How to Use This Lab

1. Review the Terraform files — find and fix the bugs
2. Run `terraform init && terraform plan` to see errors
3. Fix the issues in main.tf
4. Run `terraform plan` to verify no errors remain
5. (Optional) `terraform apply` if using a real AWS account or KodeKloud Playground

**Requires:** Terraform installed. AWS credentials for apply (optional — you can learn from plan alone).

## Validation

Run `./validate.sh` or manually verify with `terraform plan` showing no unexpected changes.
