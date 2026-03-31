# Hints — Lab 091: ClickOps Reverse Engineering

## Hint 1 — Use the project tag to scope your search
Every resource was tagged with `Project = clickops-lab-091`. Start broad:
```bash
aws ec2 describe-vpcs --filters "Name=tag:Project,Values=clickops-lab-091" --region eu-west-2
```
Then work outward from the VPC to find what's attached to it.

## Hint 2 — Discovery is a tree, not a list
Start with the VPC, then ask: what subnets are in this VPC? What internet gateways? What route tables? What security groups? Each answer leads to the next question.

## Hint 3 — The import command needs the resource ID
`terraform import` syntax is: `terraform import aws_<type>.<name> <id>`. For example:
```bash
terraform import aws_vpc.main vpc-0abc123def456
```
You need to write the Terraform resource block FIRST, then import.

## Hint 4 — Plan will show drift after import
After importing, `terraform plan` will likely show differences between your code and reality. That's normal — it means your `.tf` code doesn't perfectly match what exists. Adjust your code until plan shows "No changes."

## Hint 5 — Don't forget non-EC2 resources
There's more than just networking in this environment. Think about storage and identity.

## Hint 6 — Import order matters
Import the VPC first, then subnets, then things that depend on subnets. If you try to import a subnet before the VPC exists in state, Terraform won't know what VPC it belongs to.

## Hint 7 — Some resources need special import syntax
- S3 buckets: `terraform import aws_s3_bucket.name bucket-name`
- IAM roles: `terraform import aws_iam_role.name role-name`
- Security groups: `terraform import aws_security_group.name sg-0abc123`
- Route table associations need their own import
