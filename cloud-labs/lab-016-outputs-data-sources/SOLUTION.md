# Solution Walkthrough — Outputs and Data Sources

## The Problem

The Terraform configuration can't find the AMI it needs and isn't exposing the right information for other modules. There are **three bugs**:

1. **Hardcoded AMI ID that doesn't exist** — the instance uses `ami = "ami-0123456789abcdef0"`, which is a fake AMI that doesn't exist in any region. AMI IDs are region-specific and change over time — they should never be hardcoded.
2. **Missing outputs** — other modules or teams need to reference the VPC ID, subnet ID, instance ID, and private IP, but no outputs are defined. Without outputs, downstream resources can't reference these values.
3. **Misleading output** — the `app_public_ip` output references `private_ip` but is described as "The public IP." The description doesn't match the value, causing confusion. Since the instance has no public IP, the output should be renamed to `app_private_ip`.

## Thought Process

When Terraform can't find an AMI or downstream modules can't access values, an experienced engineer:

1. **Replace hardcoded AMIs with data sources** — the `aws_ami` data source dynamically finds the latest AMI matching your criteria. This is future-proof and region-independent.
2. **Define outputs for every value other resources need** — outputs are the interface between modules. If another team or module needs a VPC ID, it must be an output.
3. **Ensure output names and descriptions match** — misleading outputs cause integration bugs. If the value is a private IP, name it `private_ip`, not `public_ip`.

## Step-by-Step Solution

### Step 1: Fix Bug 1 — Replace hardcoded AMI with a data source

```hcl
# BROKEN
resource "aws_instance" "app" {
  ami = "ami-0123456789abcdef0"    # Fake AMI — doesn't exist!
}

# FIXED — use a data source
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]   # Canonical (Ubuntu publisher)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_instance" "app" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.app.id
  tags = { Name = "app-server" }
}
```

**Why this matters:** AMI IDs are region-specific — `ami-abc123` in `us-east-1` is a completely different image (or doesn't exist) in `eu-west-2`. The `aws_ami` data source queries AWS for the latest AMI matching your filters:
- **`most_recent = true`** — gets the newest AMI (latest security patches)
- **`owners = ["099720109477"]`** — Canonical's AWS account ID (the official Ubuntu publisher)
- **`filter`** — matches the AMI name pattern for Ubuntu 22.04 on AMD64

This works in any region and always gets the latest AMI.

### Step 2: Fix Bug 2 — Add missing outputs

```hcl
output "vpc_id" {
  value       = aws_vpc.main.id
  description = "The ID of the VPC"
}

output "subnet_id" {
  value       = aws_subnet.app.id
  description = "The ID of the application subnet"
}

output "instance_id" {
  value       = aws_instance.app.id
  description = "The ID of the application EC2 instance"
}

output "instance_private_ip" {
  value       = aws_instance.app.private_ip
  description = "The private IP address of the app server"
}
```

**Why this matters:** Outputs serve two purposes:
1. **Module interface** — when this configuration is used as a module, outputs are the only way to expose values to the parent module. Without outputs, `module.network.vpc_id` would fail.
2. **Visibility** — `terraform output` shows all output values after apply. This is useful for scripts, CI/CD pipelines, and other automation that needs resource IDs.

### Step 3: Fix Bug 3 — Fix the misleading output

```hcl
# BROKEN — name says "public" but value is private
output "app_public_ip" {
  value       = aws_instance.app.private_ip
  description = "The public IP of the app server"
}

# FIXED — name and description match the value
output "app_private_ip" {
  value       = aws_instance.app.private_ip
  description = "The private IP address of the app server"
}
```

**Why this matters:** If a downstream module uses this output expecting a public IP, it would get a private IP instead — causing connection failures. Names and descriptions should accurately describe the value.

### Step 4: Validate

```bash
terraform validate
terraform plan
```

**What this does:** Confirms the data source lookup works and all outputs are defined correctly.

## Docker Lab vs Real Life

- **AMI data sources in CI/CD:** Production pipelines use data sources to automatically pick up the latest hardened AMI from your organization's AMI pipeline. This ensures instances always have the latest security patches.
- **SSM Parameter Store for AMIs:** Some teams publish their latest AMI ID to SSM Parameter Store: `data "aws_ssm_parameter" "ami" { name = "/golden-ami/latest" }`. This provides more control than wildcard AMI lookups.
- **Output sensitivity:** Terraform supports `sensitive = true` on outputs to redact values from CLI output: `output "password" { value = ...; sensitive = true }`.
- **Remote state data source:** To read outputs from another Terraform state: `data "terraform_remote_state" "network" { backend = "s3"; config = { bucket = "state-bucket"; key = "network.tfstate" } }`. Then reference as `data.terraform_remote_state.network.outputs.vpc_id`.
- **Data source vs resource:** Data sources read existing infrastructure. Resources create/manage infrastructure. Use data sources for things you don't manage (AMIs, availability zones, account IDs).

## Key Concepts Learned

- **Never hardcode AMI IDs** — use `data "aws_ami"` to dynamically find the correct AMI for the current region. AMI IDs are region-specific and change with updates.
- **Outputs are a module's public interface** — any value that another module, script, or team needs must be an output. Without outputs, the values are trapped inside the module.
- **Data sources read existing resources** — they don't create anything. They query AWS (or other providers) and return attributes you can reference in your configuration.
- **Output names should match their values** — a misleading output is worse than a missing one. Keep names, descriptions, and values consistent.
- **`most_recent = true` gets the latest AMI** — combined with owner and name filters, this ensures you always use the most up-to-date image.

## Common Mistakes

- **Hardcoding AMI IDs** — this is the most common Terraform mistake for beginners. The AMI works in one region, fails in another, and becomes outdated when new versions are published.
- **Not specifying `owners` on AMI data sources** — without owners, the data source searches ALL public AMIs, which is slow and can return unexpected results (including community or malicious AMIs).
- **Forgetting to add outputs when refactoring into modules** — when you extract code into a module, values that were directly accessible now need explicit outputs. This is a common source of "unknown value" errors.
- **Not using `description` on outputs** — descriptions document what each output contains. Without them, downstream teams have to read your code to understand what they're getting.
- **Referencing `public_ip` on instances without public IPs** — if the instance doesn't have `associate_public_ip_address = true` or isn't in a public subnet, `public_ip` is empty. Use `private_ip` for private instances.
