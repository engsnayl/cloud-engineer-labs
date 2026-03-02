# Hints — Cloud Lab 012: Terraform Import

## Hint 1 — Import syntax
`terraform import <resource_type>.<resource_name> <aws_resource_id>`
Example: `terraform import aws_vpc.main vpc-abc123`

## Hint 2 — Find resource IDs
Use AWS CLI: `aws ec2 describe-vpcs --filters "Name=tag:Name,Values=production-vpc"` to find the VPC ID.

## Hint 3 — After import
Run `terraform plan` — it should show no changes if your config matches the imported resource. If there are differences, adjust your config to match reality.
