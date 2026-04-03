# Lab 062 — Module Won't Apply (Dependency Issues)
## Solution Walkthrough

---

## TLDR — Plain English Summary

You've refactored your Terraform code into modules — a VPC module and an EC2 module. But now `terraform plan` is throwing errors. Nothing is broken in AWS yet because nothing has been applied, but Terraform is refusing to even generate a plan.

The reason is simple: **your EC2 module is trying to reference the VPC module by the wrong name, and asking for an output that doesn't exist under that name.**

Think of it like this. You've given the VPC module a name badge that says `vpc`. But in your EC2 module, you're asking to speak to someone called `networking`. Nobody by that name works here — so Terraform refuses. On top of that, even if you corrected the name, you're asking for a piece of information called `private_subnet`, but the VPC module has labelled that information `private_subnet_id`. Wrong name, wrong label — two problems, both fixable in `main.tf`.

**The fix:** Correct the module name from `module.networking` to `module.vpc`, and correct the output name from `module.vpc.private_subnet` to `module.vpc.private_subnet_id`.

---

## The Two Bugs

| # | Bug | Where | What's wrong |
|---|-----|--------|--------------|
| 1 | Wrong module name | `main.tf` — ec2 module block | References `module.networking` but the module is declared as `module "vpc"` |
| 2 | Wrong output name | `main.tf` — ec2 module block | References `module.vpc.private_subnet` but the VPC module exports `private_subnet_id` |

---

## Investigative Learning Pathway

This section walks you through the thought process an experienced engineer uses — not just what to fix, but how to find it, why it's wrong, and how you'd reason through it in a real production incident.

---

### Stage 1 — Run it and read what breaks

**What you do:**

```bash
terraform init
terraform plan
```

| Command | What it does |
|---------|-------------|
| `terraform init` | Downloads providers, initialises modules, sets up the local `.terraform/` directory. Must be run before any other Terraform command, and re-run any time you add or change a module source path. |
| `terraform plan` | Reads your `.tf` files, compares them against current state, and produces a preview of what would be created/changed/destroyed. Does not touch real infrastructure. |

**What you see:** Terraform errors. Don't panic — Terraform error messages for module reference problems are very specific. Read them carefully before touching any code. The error will say something like:

```
A managed resource 'module.networking' has not been declared in the root module.
```

**What this tells you:**
Terraform is saying "you've asked me to look up something called `module.networking`, but I've never been told that anything by that name exists." This is your first bug, right there in the error message.

> **Real-world parallel:** In a production incident, the first instinct is often to jump straight to the code. Resist that. Terraform errors tell you the exact thing that's wrong. Train yourself to read the full error before touching anything.

---

### Stage 2 — Understand why the name matters

Before fixing anything, understand the rule:

Terraform module references follow this exact pattern:

```
module.<LABEL>.<OUTPUT_NAME>
```

The `LABEL` is not the folder path. It's not the module description. It's the name you gave it in the `module` block in `main.tf`. Look at how the VPC module is declared:

```hcl
module "vpc" {
  source = "./modules/vpc"
  ...
}
```

The label here is `vpc`. So the correct reference is `module.vpc`. Full stop. It doesn't matter that the source folder might be called `networking`, or that you might think of it as "the networking module" — Terraform only knows the label.

**How to check the declared module names:**

```bash
grep -n 'module "' main.tf
```

| Part | What it does |
|------|-------------|
| `grep` | Searches for a text pattern in a file |
| `-n` | Prints the line number alongside each match — useful for navigating large files |
| `'module "'` | The pattern to search for — matches any line declaring a module block |
| `main.tf` | The file to search in |

This prints every module declaration in your root `main.tf` with line numbers. You'll immediately see that `networking` doesn't appear anywhere. Only `vpc` and `ec2` do.

> **Key insight:** The error says `module.networking` has not been declared. Running the grep above confirms there's no `module "networking"` block anywhere. That's your smoking gun.

---

### Stage 3 — Find Bug 1 and fix it

Now you know what's wrong and why. Fix the first bug:

**Open `main.tf` and find the `ec2` module block:**

```hcl
# BROKEN — as written in the lab
module "ec2" {
  source = "./modules/ec2"

  vpc_id    = module.networking.vpc_id    # Wrong: module.networking doesn't exist
  subnet_id = module.vpc.private_subnet   # Wrong: output name is incorrect
}
```

**Fix the module name:**

```hcl
vpc_id = module.vpc.vpc_id
```

**Why `module.vpc.vpc_id`?**
- `module.vpc` — because the VPC module is declared as `module "vpc"` in `main.tf`
- `.vpc_id` — because `vpc_id` is the name of the output defined in the VPC module's `outputs.tf`

---

### Stage 4 — Investigate Bug 2 before assuming you know the fix

You've corrected the module name. Now the subnet reference needs fixing too:

```hcl
subnet_id = module.vpc.private_subnet   # Still wrong — output name is off
```

But wait — before you change `private_subnet` to `private_subnet_id`, **check the actual outputs file first.** Don't assume. In real Terraform codebases, output names vary. The only source of truth is the module's own `outputs.tf`.

**Check the VPC module's outputs:**

```bash
cat modules/vpc/outputs.tf
```

| Part | What it does |
|------|-------------|
| `cat` | Prints the full contents of a file to the terminal |
| `modules/vpc/outputs.tf` | The path to the VPC module's outputs file — this is where all values the module exposes to callers are defined |

**What you're looking for:** An `output` block with the exact name you need. For example:

```hcl
output "private_subnet_id" {
  value = aws_subnet.private.id
}
```

If you see `private_subnet_id`, your reference must be `module.vpc.private_subnet_id`. If it were named `private_subnet`, you'd use that instead. The file tells you. Never guess.

> **Why this matters:** In production, a module's output names are part of its interface contract. Changing an output name in a shared module breaks every caller of that module — potentially across dozens of Terraform root modules. This is why module versioning exists. You pin to a version so that output names don't change under you.

**Fix the output name:**

```hcl
subnet_id = module.vpc.private_subnet_id
```

---

### Stage 5 — Apply both fixes together

Your corrected `ec2` module block in `main.tf` should now look like:

```hcl
module "ec2" {
  source = "./modules/ec2"

  vpc_id    = module.vpc.vpc_id
  subnet_id = module.vpc.private_subnet_id
}
```

**How the dependency chain now works:**
1. Terraform sees that `module.ec2` depends on outputs from `module.vpc`
2. Terraform automatically creates the VPC resources first
3. Once VPC outputs are available, Terraform passes them as variables into the EC2 module
4. EC2 resources are created using those values

This is the core principle of Terraform module composition: **modules don't share state automatically — they communicate explicitly through variables (in) and outputs (out).**

---

### Stage 6 — Verify the fix

```bash
terraform plan
```

If both bugs are fixed, the plan runs to completion. You'll see the planned resources — no errors.

**Then run validation:**

```bash
./validate.sh
```

| Part | What it does |
|------|-------------|
| `./` | Runs a script from the current directory |
| `validate.sh` | A lab-provided script that runs `terraform validate` and `terraform plan` and checks for errors |

`terraform validate` is worth understanding separately:

```bash
terraform validate
```

| What it checks | What it doesn't check |
|----------------|----------------------|
| Syntax errors in `.tf` files | Whether your AWS credentials are valid |
| Invalid references (wrong module names, missing outputs) | Whether the resources will actually deploy successfully |
| Missing required variables | Runtime failures or quota limits |

It's a fast, local check — no AWS calls, no state file needed. Good to run after any change before committing.

---

## Module Reference Rules — Quick Summary

| Rule | Example |
|------|---------|
| Reference a module using its label, not its source path | `module.vpc` not `module.networking` even if source is `./modules/networking` |
| Output names must match exactly | `module.vpc.private_subnet_id` not `module.vpc.private_subnet` |
| Always check `outputs.tf` for exact names | `cat modules/vpc/outputs.tf` |
| Re-run `terraform init` after changing module sources | Source path changes require re-initialisation |

---

## Common Mistakes

**Confusing module label with source path**
`module "vpc" { source = "./modules/networking" }` means the reference is `module.vpc`, not `module.networking`. The label (the word in quotes after `module`) is what you use. The source path is just a filesystem pointer.

**Referencing resources directly instead of outputs**
You cannot write `module.vpc.aws_subnet.private.id`. You can only access values that are explicitly declared in an `output` block in `modules/vpc/outputs.tf`. If the output doesn't exist, you must add it to the module.

**Forgetting `terraform init` after adding modules**
If you add a new module block or change a source path, Terraform won't know about it until you re-run `terraform init`. The plan will fail.

**Circular dependencies**
If Module A needs an output from Module B, and Module B needs an output from Module A, Terraform cannot resolve the order. Restructure so dependencies flow in one direction only.

---

## Real-World Context

| Lab behaviour | Production reality |
|--------------|-------------------|
| Modules sourced locally with `./modules/vpc` | Modules published to Terraform Registry with versioned releases (`source = "terraform-aws-modules/vpc/aws"`, `version = "~> 5.0"`) |
| Two modules | Layered module stacks — VPC → ECS, RDS, ALB, WAF all consuming the same VPC outputs |
| Manual wiring via `main.tf` | Many teams use Terragrunt `dependency` blocks to auto-wire module outputs |
| Output names found by reading the file | Well-maintained modules publish `terraform-docs`-generated READMEs listing every input and output |

---

## Cleanup

This lab validates with `terraform plan` only — there is no need to run `terraform apply`. If you did apply, destroy first:

```bash
terraform destroy -auto-approve
```

| Part | What it does |
|------|-------------|
| `terraform destroy` | Removes all infrastructure managed by this Terraform configuration |
| `-auto-approve` | Skips the interactive confirmation prompt |

> If you haven't applied anything, skip this step.

---

## Reset — Restore the Lab to Broken Starting State

Run this to restore `main.tf` back to the broken state so the lab can be run again from scratch:

```bash
cat > main.tf << 'EOF'
provider "aws" {
  region = "eu-west-2"
}

module "vpc" {
  source = "./modules/vpc"
}

module "ec2" {
  source    = "./modules/ec2"
  vpc_id    = module.networking.vpc_id
  subnet_id = module.vpc.private_subnet
}
EOF
```

| Part | What it does |
|------|-------------|
| `cat > main.tf` | Writes output directly into `main.tf`, overwriting whatever is currently there |
| `<< 'EOF'` | Starts a heredoc — everything between here and the closing `EOF` is treated as the file content. Single quotes around `EOF` prevent variable expansion inside the block |
| `EOF` | Closes the heredoc and triggers the write |

After running this, `terraform plan` will fail again with the two reference errors — the lab is ready to repeat.

---

## Pi / K3s Notes

This is a Terraform/AWS lab — no K3s involvement. Ensure:
- AWS CLI is configured with valid credentials: `aws sts get-caller-identity`
- You're working in the correct lab directory on the Pi: `~/cloud-engineer-labs/terraform-labs/lab-062-...`
- Terraform ARM64 binary is on your PATH: `terraform version`
