# Solution — Lab 091: ClickOps Reverse Engineering — Discover & Codify

---

## TLDR

A startup has AWS resources that were created by clicking through the console over 3 years. The original engineer left and nobody documented anything. Your job is to discover what exists using AWS CLI commands, document everything, write Terraform code that describes each resource, import each resource into Terraform state, and iterate until `terraform plan` shows "No changes." This is one of the most common consulting engagements in cloud engineering — companies call it "ClickOps remediation" or "IaC migration."

---

## Background Theory

### What Is ClickOps?

ClickOps means creating and managing infrastructure by clicking through the AWS console (or any cloud provider's GUI). It works fine when you're small — one engineer, a handful of resources, everything in their head. It breaks down when:

- The engineer leaves and nobody knows what exists or why
- The company needs to prove to auditors that infrastructure is documented and version-controlled
- Anyone needs to recreate the environment (disaster recovery, staging, new region)
- Multiple people need to make changes without stepping on each other

### What Is terraform import?

Terraform normally manages resources it created. But `terraform import` tells Terraform: "this resource already exists in AWS — here's its ID — please start tracking it." After importing, Terraform compares your `.tf` code against the real resource and shows any differences in `terraform plan`.

The workflow is:

1. Write a Terraform resource block describing what you think exists
2. Run `terraform import <resource_address> <resource_id>`
3. Run `terraform plan` to see if your code matches reality
4. Fix any differences in your `.tf` code
5. Repeat until `terraform plan` shows "No changes"

### Why Import Order Matters

Terraform tracks dependencies. If your code says a subnet belongs to a VPC, Terraform needs the VPC in state first. The general rule is: import parent resources before child resources.

---

## Step-by-Step Learning Pathway

### Step 1 — Run the Setup Script

```bash
cd ~/cloud-engineer-labs/cloud-labs/lab-091-clickops-reverse-engineering
./setup.sh
```

This creates the "ClickOps" environment. The script tells you one starting command. From this point, you're on your own to discover everything else.

### Step 2 — Start Discovery with the VPC

The setup script gave you a hint: use the project tag to find the VPC. Run:

```bash
aws ec2 describe-vpcs --filters "Name=tag:Project,Values=clickops-lab-091" --region eu-west-2
```

| Part | What It Does |
|------|-------------|
| `aws ec2 describe-vpcs` | Lists VPCs in the account |
| `--filters "Name=tag:Project,Values=clickops-lab-091"` | Only show VPCs with this specific tag |
| `--region eu-west-2` | Look in the London region |

This gives you the VPC ID and CIDR block. Write both down in `DISCOVERY.md`.

**How would I know to do this?** In real life, you'd ask: "Is there anything that identifies these resources — a naming convention, a tag, a specific account?" Tags are the standard way to scope discovery.

### Step 3 — Discover What's Inside the VPC

Now you know the VPC ID. Use it to find everything attached to it:

**Subnets:**

```bash
aws ec2 describe-subnets --filters "Name=vpc-id,Values=<VPC_ID>" --region eu-west-2
```

This returns all subnets in the VPC. Note down each subnet's ID, CIDR, availability zone, and Name tag.

**Internet Gateways:**

```bash
aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=<VPC_ID>" --region eu-west-2
```

**Route Tables:**

```bash
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=<VPC_ID>" --region eu-west-2
```

Note: this will return the main (default) route table AND any custom route tables. You only need to import custom ones — the main route table is created automatically with the VPC.

**Security Groups:**

```bash
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=<VPC_ID>" --region eu-west-2
```

This will return the default security group AND any custom ones. You only need to import custom security groups. The default one is created automatically with the VPC.

**How would I know to check all of these?** This is the tree-walk approach: VPC is the root, and you ask "what types of resource can live inside a VPC?" — subnets, gateways, route tables, security groups, network ACLs, endpoints. Check each one.

### Step 4 — Discover Non-VPC Resources

Not everything lives inside a VPC. Use the project tag to find other resources:

**S3 Buckets:**

S3 doesn't support tag-based filtering in `list-buckets`. You need to list all buckets and check tags:

```bash
aws s3api list-buckets --region eu-west-2 --query 'Buckets[].Name' --output text
```

Then for each bucket that looks like it could be from this lab:

```bash
aws s3api get-bucket-tagging --bucket <bucket-name> --region eu-west-2
```

Also check versioning:

```bash
aws s3api get-bucket-versioning --bucket <bucket-name> --region eu-west-2
```

**IAM Roles:**

```bash
aws iam list-roles --query 'Roles[?contains(RoleName, `startup`)]' --output table
```

Then for the role you find:

```bash
aws iam get-role --role-name <role-name>
aws iam list-attached-role-policies --role-name <role-name>
```

| Part | What It Does |
|------|-------------|
| `aws iam get-role` | Shows the role's trust policy (who can assume it) |
| `aws iam list-attached-role-policies` | Shows what AWS managed policies are attached |

### Step 5 — Document Everything Before Writing Code

Fill out `DISCOVERY.md` completely. You should have found:

- 1 VPC
- 2 Subnets (one public, one private)
- 1 Internet Gateway
- 1 Route Table (custom, with a route to the IGW)
- 1 Route Table Association
- 1 Security Group (with HTTP, HTTPS, SSH ingress)
- 1 S3 Bucket (with versioning enabled)
- 1 IAM Role (with an EC2 trust policy and S3 read-only access)

That's 8-10 resources depending on how you count associations and attachments.

### Step 6 — Write Your Terraform Code

Create `main.tf` with a resource block for each thing you discovered. Start with:

```hcl
provider "aws" {
  region = "eu-west-2"
}
```

Then write each resource block using the values you discovered. For example, the VPC:

```hcl
resource "aws_vpc" "main" {
  cidr_block           = "10.50.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name    = "startup-vpc"
    Project = "clickops-lab-091"
  }
}
```

**Key things that trip people up:**

- Tags must match exactly — if the real resource has `Name = "startup-vpc"`, your code must too
- Security group rules: you need to describe each ingress/egress rule
- The S3 bucket's versioning is a separate resource (`aws_s3_bucket_versioning`), not an inline block
- The IAM role needs both the role itself AND an `aws_iam_role_policy_attachment` for the attached policy
- Route table associations are their own resource type (`aws_route_table_association`)

### Step 7 — Initialise Terraform

```bash
terraform init
```

This downloads the AWS provider. Then validate your syntax:

```bash
terraform validate
```

Fix any syntax errors before attempting imports.

### Step 8 — Import Resources in Dependency Order

Import parent resources first:

```bash
# 1. VPC first (everything else depends on it)
terraform import aws_vpc.main <vpc-id>

# 2. Subnets (depend on VPC)
terraform import aws_subnet.public <public-subnet-id>
terraform import aws_subnet.private <private-subnet-id>

# 3. Internet Gateway (depends on VPC)
terraform import aws_internet_gateway.main <igw-id>

# 4. Route Table (depends on VPC)
terraform import aws_route_table.public <rtb-id>

# 5. Route Table Association (depends on route table + subnet)
terraform import aws_route_table_association.public <rtb-assoc-id>

# 6. Security Group (depends on VPC)
terraform import aws_security_group.web <sg-id>

# 7. S3 Bucket (independent)
terraform import aws_s3_bucket.assets <bucket-name>

# 8. S3 Bucket Versioning (depends on bucket)
terraform import aws_s3_bucket_versioning.assets <bucket-name>

# 9. IAM Role (independent)
terraform import aws_iam_role.web <role-name>

# 10. IAM Policy Attachment (depends on role)
terraform import aws_iam_role_policy_attachment.web_s3 <role-name>/<policy-arn>
```

| Part | What It Does |
|------|-------------|
| `terraform import` | Tells Terraform to start tracking an existing resource |
| `aws_vpc.main` | The resource address in your `.tf` code — must match what you wrote |
| `<vpc-id>` | The actual AWS resource ID from your discovery |

### Step 9 — Iterate Until Plan Shows No Changes

After importing, run:

```bash
terraform plan
```

It will almost certainly show differences. Common ones:

| Plan Says | What's Wrong | Fix |
|-----------|-------------|-----|
| `~ tags` will be updated | Your tags don't match exactly | Copy the exact tag values from `describe` output |
| `+ ingress rule` will be added | You're missing a security group rule | Add the missing rule to your code |
| `~ enable_dns_hostnames` | You forgot `enable_dns_hostnames = true` on the VPC | Add it |
| Forces replacement | A fundamental attribute is wrong (wrong CIDR, wrong AZ) | Fix the value — don't let Terraform recreate it |

Read each planned change carefully. Adjust your `.tf` code. Run `terraform plan` again. Repeat until you see:

```
No changes. Your infrastructure matches the configuration.
```

That's the finish line.

### Step 10 — Validate

```bash
./validate.sh
```

---

## Command Breakdown

### terraform import

| Part | What It Does |
|------|-------------|
| `terraform` | The Terraform CLI |
| `import` | Import subcommand — links an existing resource to your code |
| `aws_vpc.main` | Resource address: `<provider>_<type>.<name>` matching your `.tf` code |
| `vpc-0abc123` | The real AWS resource ID to import |

### terraform plan -detailed-exitcode

| Part | What It Does |
|------|-------------|
| `terraform plan` | Compares your code against state and shows what would change |
| `-detailed-exitcode` | Returns exit code 0 = no changes, 1 = error, 2 = changes pending |

### aws ec2 describe-subnets --filters

| Part | What It Does |
|------|-------------|
| `describe-subnets` | Lists subnets |
| `--filters "Name=vpc-id,Values=..."` | Only subnets belonging to this specific VPC |
| `--query 'Subnets[].{...}'` | JMESPath query to extract specific fields from the JSON response |
| `--output table` | Display as a readable table instead of raw JSON |

### aws iam list-attached-role-policies

| Part | What It Does |
|------|-------------|
| `list-attached-role-policies` | Shows AWS managed policies attached to a role |
| `--role-name` | Which role to check |
| Returns `PolicyArn` | You need this ARN for the `aws_iam_role_policy_attachment` import |

---

## Cleanup / Reset

**Always run teardown when you're done — these are real AWS resources that cost money:**

```bash
./teardown.sh
```

To reset and try again from scratch:

```bash
# Destroy existing resources
./teardown.sh

# Remove any Terraform files you created
rm -f main.tf terraform.tfstate terraform.tfstate.backup
rm -rf .terraform .terraform.lock.hcl

# Re-run setup to create fresh resources
./setup.sh
```

The `DISCOVERY.md` worksheet resets with `git checkout -- DISCOVERY.md`.
