# Solution Walkthrough — Module Won't Apply (Dependency Issues)

## The Problem

A modular Terraform configuration fails with dependency errors. The infrastructure was refactored from a flat configuration into modules (`vpc` and `ec2`), but the references between modules are broken. There are **two bugs**:

1. **Wrong module name** — the `ec2` module references `module.networking.vpc_id`, but the VPC module is named `module.vpc`, not `module.networking`. Terraform can't find a module called `networking` because it doesn't exist.
2. **Wrong output name** — the `ec2` module references `module.vpc.private_subnet`, but the VPC module's output is likely called `private_subnet_id` (or similar). The output name must match exactly what the module exports.

Both bugs produce errors during `terraform plan` because Terraform can't resolve the references.

## Thought Process

When Terraform module references fail, an experienced engineer:

1. **Read the error message** — Terraform error messages for module reference issues are very specific: "A managed resource 'module.networking' has not been declared in the root module." This tells you exactly which reference is broken.
2. **Check module names** — the name after `module.` must match the label in the `module "label" {}` block. If the block says `module "vpc"`, you reference it as `module.vpc`.
3. **Check module outputs** — look at the module's `outputs.tf` file to see the exact output names. `module.vpc.private_subnet` only works if the VPC module has `output "private_subnet" {}`.
4. **Trace the dependency chain** — modules that depend on other modules must pass values explicitly through variables and outputs. There's no implicit sharing.

## Step-by-Step Solution

### Step 1: Try to initialize and plan

```bash
terraform init
terraform plan
```

**What this does:** `terraform init` downloads providers and initializes modules. `terraform plan` will fail with errors showing which references are broken. You'll see errors like:
- `No module call named "networking" is declared in the root module` — the first bug
- Output reference errors — the second bug

### Step 2: Fix Bug 1 — Correct the module name reference

In `main.tf`, find the `ec2` module:

```hcl
# BROKEN: module.networking doesn't exist — it's called module.vpc
module "ec2" {
  source = "./modules/ec2"

  vpc_id    = module.networking.vpc_id    # Wrong module name!
  subnet_id = module.vpc.private_subnet   # Wrong output name!
}
```

Change `module.networking.vpc_id` to `module.vpc.vpc_id`:

```hcl
module "ec2" {
  source = "./modules/ec2"

  vpc_id    = module.vpc.vpc_id
  subnet_id = module.vpc.private_subnet_id
}
```

**Why this matters:** Terraform module references follow the pattern `module.<MODULE_LABEL>.<OUTPUT_NAME>`. The module label is the name you gave it in the `module` block declaration. The VPC module is declared as `module "vpc"`, so you reference it as `module.vpc` — not `module.networking`, `module.network`, or any other name.

### Step 3: Fix Bug 2 — Correct the output name

The reference `module.vpc.private_subnet` should be `module.vpc.private_subnet_id`. Check the VPC module's outputs to see the exact name:

```bash
cat modules/vpc/outputs.tf
```

**What this does:** Shows the actual output names defined in the VPC module. Match your references to these exact names. If the output is:

```hcl
output "private_subnet_id" {
  value = aws_subnet.private.id
}
```

Then your reference must be `module.vpc.private_subnet_id` — not `module.vpc.private_subnet`.

**Note:** In this lab, the modules directory may not be pre-created. The important thing is understanding that the `main.tf` references must match the module definitions. If the modules need to be created, they would contain the VPC resources and export the needed outputs.

### Step 4: Verify the module structure

If the modules directory exists, check both modules:

```bash
ls modules/vpc/
ls modules/ec2/
```

The VPC module should have:
- `main.tf` — VPC, subnets, IGW, NAT Gateway, route tables
- `outputs.tf` — exports `vpc_id`, `private_subnet_id`, etc.
- `variables.tf` — any input variables

The EC2 module should have:
- `main.tf` — EC2 instance, security group
- `variables.tf` — accepts `vpc_id` and `subnet_id` as inputs

### Step 5: Run plan to verify

```bash
terraform plan
```

**What this does:** With the references fixed, Terraform can now resolve the dependency chain: VPC module creates resources and exports outputs → EC2 module receives those outputs as variables. The plan should complete without errors.

### Step 6: Run validation

```bash
./validate.sh
```

**What this does:** Runs `terraform validate` and `terraform plan` to confirm the configuration is valid and error-free.

## Docker Lab vs Real Life

- **Module registries:** In production, modules are published to the Terraform Registry (public or private) with versioned releases. Instead of `source = "./modules/vpc"`, you'd use `source = "terraform-aws-modules/vpc/aws"` with a version pin.
- **Module versioning:** Production modules use version constraints: `version = "~> 5.0"`. This prevents breaking changes from being pulled in automatically.
- **Module composition:** Real infrastructure uses layered modules — a VPC module outputs IDs that feed into an ECS module, a RDS module, and an ALB module. Getting the output names right across 5+ modules is a common challenge.
- **Terragrunt:** Many teams use Terragrunt to manage module dependencies, automatically passing outputs from one module to another using `dependency` blocks. This reduces manual wiring errors.
- **Module documentation:** Well-maintained modules have README files listing all inputs and outputs. The `terraform-docs` tool auto-generates this documentation from the code.

## Key Concepts Learned

- **Module references use `module.<LABEL>.<OUTPUT>`** — the label must match the `module "label" {}` block name exactly. The output must match an `output` block in the module.
- **Terraform error messages are very specific** — "No module call named 'networking'" tells you the exact module name that's wrong. Read errors carefully before changing code.
- **Modules communicate through inputs (variables) and outputs** — the parent module passes values to child modules via variables, and reads results via outputs. There's no implicit sharing or inheritance.
- **`terraform init` must be re-run when module sources change** — if you change the `source` path of a module, you need to re-run `terraform init` to initialize the new module location.
- **Output names are part of a module's interface** — changing an output name in a module breaks all callers. This is why module versioning is important in production.

## Common Mistakes

- **Confusing module name with module source** — `module "vpc" { source = "./modules/networking" }` means the reference is `module.vpc`, not `module.networking`. The label (first argument) is what you use in references, not the source path.
- **Referencing resources instead of outputs** — you can't write `module.vpc.aws_subnet.private.id`. You can only reference outputs defined in the module's `outputs.tf`. If an output doesn't exist, add it to the module.
- **Circular dependencies between modules** — if module A depends on module B, and module B depends on module A, Terraform will error. Restructure your modules to have a clear dependency direction.
- **Forgetting to run `terraform init` after adding modules** — new modules (or changed source paths) require re-initialization. Without init, Terraform doesn't know about the module.
- **Typos in output names** — `private_subnet` vs `private_subnet_id` is a single-word difference that causes a hard error. Always check `outputs.tf` for exact names.
