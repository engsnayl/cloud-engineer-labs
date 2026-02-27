Title: Private Subnet Can't Reach AWS Services — NAT Gateway & VPC Endpoints
Difficulty: ⭐⭐⭐ (Advanced)
Time: 20-25 minutes
Category: AWS / Networking
Skills: VPC, NAT Gateway, VPC Endpoints, route tables, subnets, Terraform

## Scenario

An application running in a private subnet needs to access S3 and the internet for package updates. The VPC has a NAT Gateway and a VPC Endpoint for S3, but neither is working. The EC2 instance can't reach anything outside the VPC.

> **INCIDENT-NET-002**: Application in private subnet cannot pull Docker images or access S3. Instance has no internet connectivity despite NAT Gateway being provisioned. S3 VPC Endpoint exists but S3 operations time out.

## Objectives

1. Fix the NAT Gateway placement (must be in a public subnet)
2. Fix the route table for the private subnet to route through the NAT Gateway
3. Fix the VPC Endpoint route table association
4. Fix the VPC Endpoint policy so it allows S3 access
5. `terraform validate` must pass
6. `terraform plan` must complete without errors

**Requires:** Terraform installed. AWS credentials for apply (optional).

## Validation

Run `./validate.sh` or manually verify with `terraform plan`.
