# Solution Walkthrough — Terraform Import and Resource Adoption

## The Problem

Resources were created manually in the AWS console and now need to be brought under Terraform management. The Terraform configuration (`.tf` files) already describes the resources, but the state file doesn't know about them. Running `terraform apply` would try to create **duplicate** resources instead of managing the existing ones.

The task is to **import** the existing AWS resources into Terraform state so that Terraform recognizes and manages them going forward.

## Thought Process

When adopting manually-created resources into Terraform, an experienced engineer follows this process:

1. **Write the Terraform config first** — create `.tf` files that describe the existing resources as accurately as possible. Match every attribute (CIDR blocks, tags, names, etc.) to the real resource.
2. **Find the resource IDs** — use the AWS console or CLI to get the actual resource IDs (VPC ID, subnet ID, security group ID, etc.).
3. **Import each resource** — use `terraform import` to link each Terraform resource block to its real AWS counterpart.
4. **Run plan to check for drift** — after importing, `terraform plan` shows any differences between your config and reality. Adjust the config until the plan shows no changes.

## Step-by-Step Solution

### Step 1: Review the existing Terraform configuration

The `main.tf` already describes three resources that exist in AWS:

```hcl
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "production-vpc" }
}

resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  tags = { Name = "public-subnet" }
}

resource "aws_security_group" "web" {
  name   = "web-sg"
  vpc_id = aws_vpc.main.id
  # ... ingress/egress rules
}
```

### Step 2: Find the resource IDs in AWS

Use the AWS CLI to find the actual resource IDs:

```bash
# Find the VPC ID
aws ec2 describe-vpcs --filters "Name=tag:Name,Values=production-vpc" \
  --query 'Vpcs[0].VpcId' --output text

# Find the subnet ID
aws ec2 describe-subnets --filters "Name=tag:Name,Values=public-subnet" \
  --query 'Subnets[0].SubnetId' --output text

# Find the security group ID
aws ec2 describe-security-groups --filters "Name=group-name,Values=web-sg" \
  --query 'SecurityGroups[0].GroupId' --output text
```

**What this does:** Queries AWS for the real resource IDs. You'll get IDs like `vpc-abc12345`, `subnet-def67890`, `sg-ghi11111`.

### Step 3: Initialize Terraform

```bash
terraform init
```

**What this does:** Initializes the provider. This is required before importing.

### Step 4: Import each resource

```bash
terraform import aws_vpc.main vpc-abc12345
terraform import aws_subnet.public subnet-def67890
terraform import aws_security_group.web sg-ghi11111
```

**What this does:** Each `terraform import` command:
1. Reads the real resource from AWS using its ID
2. Records the resource's current state in the Terraform state file
3. Links the state entry to the resource block in your `.tf` file

The syntax is: `terraform import <resource_type>.<resource_name> <aws_resource_id>`

After importing, Terraform "knows" about the existing resources and won't try to create duplicates.

### Step 5: Check for drift

```bash
terraform plan
```

**What this does:** Compares your `.tf` configuration with the imported state. If the plan shows "No changes," your config perfectly matches reality. If there are differences (e.g., a tag you forgot, a different CIDR block), either:
- Update your `.tf` config to match reality (if the existing setting is correct)
- Leave your config as-is and let Terraform apply the change (if you want to modify the resource)

### Step 6: Adjust configuration if needed

If `terraform plan` shows differences, update `main.tf` to match the real resources. For example, if the VPC has DNS support enabled in AWS but your config doesn't specify it:

```hcl
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true    # Match reality
  enable_dns_hostnames = true
  tags = { Name = "production-vpc" }
}
```

### Step 7: Validate

```bash
terraform validate
terraform plan
```

**What this does:** Confirms the configuration is valid and the plan shows either "No changes" (perfect match) or only intentional changes.

## Docker Lab vs Real Life

- **Terraform 1.5+ import blocks:** Modern Terraform supports `import` blocks directly in configuration, which is more GitOps-friendly than the CLI command:
  ```hcl
  import {
    to = aws_vpc.main
    id = "vpc-abc12345"
  }
  ```
  This can be committed to version control and run as part of `terraform apply`.
- **`terraform plan -generate-config-out`:** In Terraform 1.5+, you can auto-generate configuration from imported resources. This saves manual config writing.
- **Large-scale imports:** Tools like `terraformer` and `aws2tf` can bulk-import hundreds of existing AWS resources, generating both the configuration and import commands.
- **State manipulation risks:** `terraform import` modifies the state file. Always back up the state before importing, especially in production.
- **Partial imports:** Some resources have sub-resources that must be imported separately. For example, importing an `aws_security_group` doesn't import its rules if they're defined as separate `aws_security_group_rule` resources.

## Key Concepts Learned

- **`terraform import` links existing resources to Terraform config** — it doesn't create or modify infrastructure. It only updates the state file.
- **Config must match reality after import** — if your `.tf` file says one thing and AWS says another, `terraform plan` will show changes. Align them to avoid unintended modifications.
- **Import syntax: `terraform import <type>.<name> <id>`** — the resource type and name come from your `.tf` file, the ID comes from AWS.
- **Import doesn't generate configuration** — you must write the `.tf` files yourself (or use `terraform plan -generate-config-out` in 1.5+). Import only populates the state.
- **Each resource type has its own import ID format** — VPCs use `vpc-xxx`, S3 buckets use the bucket name, IAM roles use the role name. Check the Terraform docs for each resource type.

## Common Mistakes

- **Running `terraform apply` before importing** — this creates duplicate resources. Always import first, then plan, then apply (if needed).
- **Mismatched configuration after import** — if your config doesn't match the real resource, the next `terraform apply` will modify or recreate the resource. Always run `terraform plan` after import to verify.
- **Wrong import ID format** — different resource types use different ID formats. Security groups use `sg-xxx`, subnets use `subnet-xxx`, S3 buckets use the bucket name (not an ARN). Check the Terraform provider docs.
- **Forgetting dependent resources** — if you import a subnet but not its VPC, Terraform will try to create a new VPC. Import all related resources together.
- **Not backing up state before import** — if an import goes wrong, you may need to manually edit the state or start over. Always back up: `cp terraform.tfstate terraform.tfstate.backup`.
