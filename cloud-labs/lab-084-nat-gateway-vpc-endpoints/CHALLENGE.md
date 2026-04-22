# Lab 084 — Private Subnet Can't Reach AWS Services

Title: Private Subnet Can't Reach AWS Services — NAT Gateway & VPC Endpoints
Difficulty: ⭐⭐⭐ (Advanced)
Time: 25-35 minutes
Category: AWS / Networking
Skills: VPC, NAT Gateway, VPC Endpoints, route tables, subnets, SSM, Terraform

## Scenario

An application team deployed a workload into a private subnet in the `lab-vpc` VPC. The instance is meant to:

- Pull OS packages and Docker images from the internet
- List objects in an S3 bucket the team owns

Neither works. An on-call engineer raised **INCIDENT-NET-002**. The VPC has a NAT Gateway and an S3 VPC Endpoint provisioned — the platform team insists "everything is there" — but the instance reports timeouts on every outbound call.

> **INCIDENT-NET-002**: Application in private subnet (`10.0.2.0/24`) cannot pull packages or access S3. `curl https://www.google.com` hangs. `aws s3 ls` hangs. Platform team says NAT Gateway and S3 VPC Endpoint are deployed. Find out why traffic isn't flowing and restore connectivity.

You've been handed the Terraform that defines the environment. Confirm the fault, find the root causes, and fix them.

## What You'll Practise

- Reproducing a network fault from inside a private subnet via SSM Session Manager
- Reading VPC topology from Terraform and the AWS console
- Reasoning about NAT Gateway placement requirements
- Distinguishing IGW routes from NAT Gateway routes in a route table
- VPC Endpoint route table associations and endpoint policies
- Validating connectivity end-to-end after each fix

## Starting point

- A Terraform configuration defining a VPC, public + private subnets, IGW, NAT Gateway, S3 VPC Endpoint, a private EC2 instance, and an S3 bucket
- An EC2 instance in the private subnet, reachable only via SSM Session Manager (no SSH, no public IP)
- An S3 bucket the instance is supposed to be able to list

## Objectives

1. Confirm the fault from inside the private EC2 instance (both internet egress and S3 access must be reachable when the lab is fixed)
2. Identify all infrastructure misconfigurations that cause the symptoms
3. Restore outbound internet connectivity for the private instance
4. Restore S3 access for the private instance
5. `./validate.sh` passes all checks against real AWS resource state

## Requirements

- Terraform installed
- AWS credentials with permission to manage VPC, EC2, IAM, S3, SSM
- Session Manager Plugin for AWS CLI (for `aws ssm start-session`)
- Region: `eu-west-2`

## Validation

After applying your fix, run `./validate.sh`. It inspects real AWS resource state — not Terraform syntax — and must return all checks passing.

## Cleanup

```bash
terraform destroy -auto-approve
```

Make sure to destroy when done. NAT Gateways and Elastic IPs incur hourly charges.
