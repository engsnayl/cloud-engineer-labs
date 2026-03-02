# Solution Walkthrough — Terraform Workspace Confusion

## The Problem

The team accidentally applied staging configuration to production because Terraform workspaces are in use but the configuration isn't workspace-aware. Every workspace gets the same settings — same instance type (`t3.micro`), same scaling (1-2 instances), and a hardcoded `Environment = "staging"` tag. There are **three bugs**:

1. **No workspace-aware configuration** — the instance type is hardcoded to `t3.micro` regardless of workspace. Production should use `t3.large` (or larger).
2. **Hardcoded environment tag** — `Environment = "staging"` is hardcoded in the tags instead of using `terraform.workspace` to set it dynamically.
3. **Same scaling for all environments** — the ASG uses `min_size = 1, max_size = 2` for all workspaces. Production needs higher scaling limits.

## Thought Process

When Terraform workspaces don't differentiate environments, an experienced engineer:

1. **Use `terraform.workspace`** — this built-in variable returns the current workspace name (e.g., "staging", "production").
2. **Create a locals map** — define a map of workspace names to configuration values. Each workspace gets its own settings.
3. **Reference the map** — use `local.env.instance_type`, `local.env.min_size`, etc. to get workspace-specific values.
4. **Tag everything with the workspace name** — `Environment = terraform.workspace` ensures every resource is tagged with its actual environment.

## Step-by-Step Solution

### Step 1: Add workspace-aware locals

Add a `locals` block that maps workspace names to environment-specific configuration:

```hcl
locals {
  config = {
    default = {
      instance_type = "t3.micro"
      min_size      = 1
      max_size      = 2
      desired       = 1
    }
    staging = {
      instance_type = "t3.micro"
      min_size      = 1
      max_size      = 2
      desired       = 1
    }
    production = {
      instance_type = "t3.large"
      min_size      = 2
      max_size      = 10
      desired       = 2
    }
  }
  env = local.config[terraform.workspace]
}
```

**Why this matters:** The `locals` block creates a lookup table. `terraform.workspace` returns the current workspace name, and `local.config[terraform.workspace]` retrieves the matching configuration. The `default` entry handles the default workspace (which always exists).

### Step 2: Fix the instance resource

```hcl
# BROKEN
resource "aws_instance" "app" {
  ami           = "ami-0c76bd4bd302b30ec"
  instance_type = "t3.micro"              # Hardcoded!
  tags = {
    Name        = "app-server"
    Environment = "staging"               # Hardcoded!
  }
}

# FIXED
resource "aws_instance" "app" {
  ami           = "ami-0c76bd4bd302b30ec"
  instance_type = local.env.instance_type
  tags = {
    Name        = "app-server-${terraform.workspace}"
    Environment = terraform.workspace
  }
}
```

### Step 3: Fix the ASG

```hcl
# BROKEN
resource "aws_autoscaling_group" "app" {
  min_size         = 1    # Same for all environments!
  max_size         = 2
  desired_capacity = 1
}

# FIXED
resource "aws_autoscaling_group" "app" {
  name                = "app-asg-${terraform.workspace}"
  min_size            = local.env.min_size
  max_size            = local.env.max_size
  desired_capacity    = local.env.desired
  vpc_zone_identifier = [aws_subnet.app.id]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }
}
```

### Step 4: Fix the launch template

```hcl
resource "aws_launch_template" "app" {
  name_prefix   = "app-${terraform.workspace}-"
  image_id      = "ami-0c76bd4bd302b30ec"
  instance_type = local.env.instance_type
}
```

### Step 5: Test with different workspaces

```bash
# Test in default workspace
terraform workspace select default
terraform plan

# Create and test staging
terraform workspace new staging
terraform plan

# Create and test production
terraform workspace new production
terraform plan
```

**What this does:** Each workspace produces a different plan — staging gets `t3.micro` with 1-2 instances, production gets `t3.large` with 2-10 instances. The same `.tf` files produce different infrastructure based on the workspace.

### Step 6: Validate

```bash
terraform validate
terraform plan
```

## Docker Lab vs Real Life

- **Workspaces vs separate directories:** Many teams prefer separate directories (or repos) for each environment instead of workspaces. Workspaces share the same code but have separate state — separate directories allow different code per environment.
- **Terragrunt for environments:** Terragrunt provides a cleaner way to manage environments with DRY (Don't Repeat Yourself) configuration. It wraps Terraform with environment-specific variables and backend configuration.
- **Variable files per environment:** An alternative to workspace maps is `terraform apply -var-file=production.tfvars`. This separates environment config from the code.
- **Workspace protection:** There's no built-in way to prevent applying to the wrong workspace. Teams add safeguards like CI/CD pipelines that automatically select the correct workspace, or pre-apply scripts that verify the workspace name.
- **State isolation:** Each workspace has its own state file, but they share the same backend configuration. In production, some teams prefer completely separate backends per environment for stronger isolation.

## Key Concepts Learned

- **`terraform.workspace` returns the current workspace name** — use it to differentiate environments in your configuration
- **Locals maps enable workspace-aware configuration** — define a map of workspace → settings, then look up `local.config[terraform.workspace]`
- **Always tag resources with the workspace/environment** — `Environment = terraform.workspace` ensures you can identify which environment owns each resource
- **Each workspace has isolated state** — resources in the "staging" workspace are completely separate from "production" workspace resources, even though they share the same `.tf` code
- **The "default" workspace always exists** — include a "default" entry in your config map to handle the workspace that Terraform creates automatically

## Common Mistakes

- **Forgetting to switch workspaces before applying** — `terraform workspace select production` must be run before `terraform apply`. Applying in the wrong workspace deploys to the wrong environment.
- **Not including a "default" workspace entry** — if your map only has "staging" and "production" but you're in the "default" workspace, the lookup fails with an error.
- **Hardcoding values instead of using the workspace map** — if even one resource doesn't use the locals lookup, it gets the same config in all environments.
- **Workspace names are case-sensitive** — "Production" and "production" are different workspaces. Standardize on lowercase.
- **Not naming resources uniquely per workspace** — without `${terraform.workspace}` in resource names, resources from different workspaces may conflict (e.g., two ASGs named "app-asg").
