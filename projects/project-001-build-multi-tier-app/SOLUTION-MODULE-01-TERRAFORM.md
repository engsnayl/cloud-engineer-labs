# Module 1 — Terraform: Networking, Security, ECR

## TL;DR

This module builds the AWS infrastructure layer for the capstone — a modular Terraform configuration in `solution/terraform/` that provisions the foundation everything else will run on.

By the end of the module:

- A modular Terraform configuration in `solution/terraform/` with three child modules: `vpc/`, `security/`, `ecr/`
- A VPC with public + private subnets across two AZs in `eu-west-1`
- Three security groups in a least-privilege chain (frontend → backend → database)
- Two ECR repositories (`multi-tier-frontend`, `multi-tier-backend`) with lifecycle policies
- Remote state in S3 with DynamoDB locking, fully wired and working

We stopped at a successful `terraform plan` — **28 resources** queued to add, all under one execution plan. The actual `apply` is held until later modules in the series so the AWS bill stays at pennies (the only resources actually created during Module 1 are the S3 state bucket and DynamoDB lock table).

**Skills demonstrated:** Terraform modules, S3 remote state, DynamoDB state locking, VPC design (multi-AZ, public/private subnets, NAT Gateway), least-privilege security groups with chained source references, ECR with lifecycle policies, provider version pinning, idempotent plans, separation of root composition from module implementation.

---

## Pre-flight checks

Before any code changes, verified:

```bash
git status                           # working tree clean, on main
aws sts get-caller-identity          # right user, right account
aws configure get region             # eu-west-1
terraform version                    # 1.10.5 on linux_arm64
```

Confirmed: IAM user `StephenNaylor`, account `340752829546`, region `eu-west-1`, Terraform v1.10.5.

The Terraform CLI's "your version is out of date" warning was deliberately ignored — 1.10.5 supports everything we need (modules, S3 backend, validation blocks). Upgrading mid-project risks state-format incompatibilities for no benefit.

---

## Design decisions

Locked in before writing any code so they weren't being made under pressure mid-build.

### Networking

| Decision | Value | Reasoning |
|---|---|---|
| VPC CIDR | `10.0.0.0/16` | Standard private range, 65k addresses |
| AZs | `eu-west-1a`, `eu-west-1b` | Two AZs satisfies multi-AZ requirement; three would mean an extra NAT |
| Public subnets | `10.0.1.0/24`, `10.0.2.0/24` | One per AZ |
| Private subnets | `10.0.10.0/24`, `10.0.20.0/24` | Numerically spaced for readability in route tables |
| NAT Gateway | 1, in public subnet AZ-a | Production wants one per AZ for HA; one is fine for a learning project and saves ~$32/month |
| Route tables | 1 public (→ IGW), 1 private (→ NAT) | Standard pattern |

### Security groups

The chain is the whole point of this module — what makes it least-privilege:

```
internet ──▶ frontend-sg (80, 443 from 0.0.0.0/0)
                │
                └──▶ backend-sg (8080, only from frontend-sg)
                          │
                          └──▶ database-sg (5432, only from backend-sg)
```

The chain uses **source security group references**, not CIDR blocks. Rules track membership, not IPs. New instance added to the backend tier? Inherits database access automatically.

These SGs are for future EC2/RDS use. The current K3s deployment runs on the Pi and doesn't consume them. They exist so the Terraform layer is complete and interview-defensible, and so the architecture is ready to migrate to EC2/EKS.

### ECR

| Decision | Value | Reasoning |
|---|---|---|
| Repositories | `multi-tier-frontend`, `multi-tier-backend` | One per image |
| Tag mutability | `MUTABLE` | Need `:latest` to be overwritable for dev. **Production should use `IMMUTABLE` + SHA tags only** |
| Scan on push | `true` | Free CVE scanning |
| Lifecycle | Keep last 10 tagged; expire untagged after 7 days | Stops registry bloat; preserves rollback |

### Remote state

| Decision | Value | Reasoning |
|---|---|---|
| Bucket | `multi-tier-app-tfstate-340752829546` | `<project>-tfstate-<account-id>`; account ID guarantees S3 global uniqueness |
| Versioning | Enabled | State files are precious — you will want to roll back one day |
| Public access | Blocked at all four levels | State contains secrets |
| Lock table | `multi-tier-app-tf-locks` | DynamoDB |
| Lock partition key | `LockID` (string) | **Hardcoded by Terraform — must be exactly this** |
| Billing | `PAY_PER_REQUEST` | Pennies/month vs provisioned mode's dollars |

---

## Build order

Bottom-up. Each layer verifiable before the next:

1. Bootstrap S3 + DynamoDB via AWS CLI (the chicken-and-egg)
2. `solution/terraform/` skeleton + `providers.tf`
3. Root `variables.tf` + `terraform.tfvars.example`
4. `modules/vpc/` (built fresh, not copied from `reference/`)
5. `modules/security/` (net-new — gap in the reference build)
6. `modules/ecr/` (built fresh)
7. Root `main.tf` (composition) + root `outputs.tf`
8. `backend.tf` — wire to remote state, run `terraform init` + `terraform plan`

---

## Step 1 — Bootstrap the remote state

Terraform's S3 backend needs the bucket and lock table to exist *before* `terraform init` reads `backend.tf`. The bootstrap is done with the AWS CLI rather than Terraform itself — chicken-and-egg.

### 1a. Set bootstrap variables

```bash
export AWS_REGION=eu-west-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export TF_STATE_BUCKET="multi-tier-app-tfstate-${AWS_ACCOUNT_ID}"
export TF_LOCK_TABLE="multi-tier-app-tf-locks"
```

The bucket name is composed as `<project>-tfstate-<account-id>`. The account ID guarantees global uniqueness in S3's flat namespace — no two accounts share an ID. The account ID itself is fetched from `aws sts get-caller-identity` rather than hardcoded, so the same script works regardless of which AWS profile is active.

### 1b. Create the S3 state bucket

```bash
aws s3api create-bucket \
  --bucket "$TF_STATE_BUCKET" \
  --region "$AWS_REGION" \
  --create-bucket-configuration LocationConstraint="$AWS_REGION"
```

| Flag | Purpose |
|---|---|
| `--bucket` | Globally-unique bucket name |
| `--region` | Where the bucket lives |
| `--create-bucket-configuration LocationConstraint=...` | Required for any region except `us-east-1` (historical AWS quirk) |

### 1c. Enable versioning + block public access

```bash
aws s3api put-bucket-versioning \
  --bucket "$TF_STATE_BUCKET" \
  --versioning-configuration Status=Enabled

aws s3api put-public-access-block \
  --bucket "$TF_STATE_BUCKET" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

Versioning enabled so accidental state corruption / deletion is recoverable. All four public-access-block flags set to `true` — defence in depth, since this bucket holds infrastructure secrets.

### 1d. Create the DynamoDB lock table

```bash
aws dynamodb create-table \
  --table-name "$TF_LOCK_TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$AWS_REGION"
```

| Flag | Purpose |
|---|---|
| `--attribute-definitions AttributeName=LockID,AttributeType=S` | Declares the `LockID` string attribute (DynamoDB only needs key attributes declared) |
| `--key-schema AttributeName=LockID,KeyType=HASH` | Makes `LockID` the partition key. **`LockID` is hardcoded by Terraform — must be exactly this name** |
| `--billing-mode PAY_PER_REQUEST` | On-demand pricing — pennies/month for a lock table vs dollars for provisioned |

### 1e. Verify

```bash
aws s3api head-bucket --bucket "$TF_STATE_BUCKET" && echo "Bucket OK"
aws s3api get-bucket-versioning --bucket "$TF_STATE_BUCKET"
aws dynamodb describe-table --table-name "$TF_LOCK_TABLE" --query 'Table.TableStatus' --output text
```

All three checks passed:
- `Bucket OK` (head-bucket returns 200)
- `Status: Enabled` (versioning is on)
- `ACTIVE` (DynamoDB table provisioned)

---

## Step 2 — Terraform skeleton + providers.tf

### 2a. Create the directory tree

```bash
cd solution
mkdir -p terraform/modules/{vpc,security,ecr}
```

The `solution/` vs `reference/` separation is deliberate. `reference/` is read-only — used for sanity-checking but never `terraform apply`'d. `solution/` is where this build lives.

### 2b. providers.tf

```hcl
terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
```

### Why each piece is there

| Block / line | Purpose |
|---|---|
| `terraform { required_version }` | Pins the Terraform CLI version. Prevents anyone running this with an incompatible CLI. HCL syntax and state format have changed across major versions — pinning means predictable behaviour |
| `required_providers { aws }` | Declares the AWS provider as a dependency, pinned to the 5.70 series |
| `version = "~> 5.70"` | **Pessimistic version constraint**: 5.70 or later, but only within the 5.x major series. Resolved to **5.100.0** at init time — the lock file pins this exact version for reproducibility |
| `provider "aws" { region }` | Pulls region from a root variable so the same code works for any region without editing |
| `default_tags` | Tags applied to every taggable resource Terraform creates. `ManagedBy = "Terraform"` is gold for ops — anyone seeing a resource in the AWS console knows immediately not to click-modify it |

---

## Step 3 — Root variables and example tfvars

### 3a. variables.tf

Eight inputs declared. Every value that might change between runs is a variable, even seemingly obvious ones like region — hardcoded values become search-and-replace nightmares the moment requirements shift.

Five variables have validation blocks. The patterns used:

| Pattern | Used for | Why |
|---|---|---|
| `can(regex(...))` | `aws_region`, `project_name` | Format check — catches typos against a regex pattern |
| `contains([...], var)` | `environment` | Explicit allowlist — only specific values permitted |
| `can(cidrnetmask(var))` | `vpc_cidr` | Built-in CIDR validity check via Terraform's CIDR functions |
| `length(var) >= n` | `availability_zones` | Collection size constraint — multi-AZ requires ≥2 |

The `can()` wrapper is the idiomatic Terraform pattern: returns `true` if the wrapped expression succeeds, `false` if it errors. Converts errors into clean validation failures.

Validation runs **at plan time**, before any AWS API calls. Bad inputs fail immediately with the configured error message — no half-provisioned resources.

### 3b. terraform.tfvars.example

A template with the same defaults as `variables.tf`. Pattern: copy to `terraform.tfvars`, edit overrides, Terraform auto-loads on plan. The real `terraform.tfvars` is `.gitignore`'d.

### 3c. Verifying validation actually works

```bash
terraform init -backend=false              # download providers, skip backend (not configured yet)
terraform validate                          # local syntax + type check, no AWS calls
terraform plan -var="environment=production"   # should fail validation
```

Verified outputs:

- `init` resolved AWS provider to v5.100.0 (within `~> 5.70` constraint), wrote `.terraform.lock.hcl`
- `validate` returned `Success! The configuration is valid.`
- `plan` failed before any API calls with: `environment must be one of: dev, staging, prod.`

The lock file pins the exact provider version for reproducible builds and is committed to the repo.

### Validation depth proportional to risk

Region and environment are high-frequency mistakes. CIDR is a format-error class problem — easy to typo, hard to debug from AWS error messages. Subnet CIDR lists *could* be validated with `alltrue` + `for` expressions, but the AWS provider rejects bad CIDRs at apply with reasonable errors, so marginal value is low. Pick validations that pay back in saved debug time.

---

## Step 4 — VPC module

The foundation. Built fresh in `solution/`, not copied from `reference/`.

### Resources created (14 total)

| Resource | Count | Purpose |
|---|---|---|
| `aws_vpc` | 1 | The VPC, `10.0.0.0/16` |
| `aws_internet_gateway` | 1 | Public-facing internet ingress/egress |
| `aws_subnet` (public) | 2 | One per AZ, for ALBs and NAT |
| `aws_subnet` (private) | 2 | One per AZ, for compute/databases |
| `aws_eip` | 1 | Static IP for the NAT Gateway |
| `aws_nat_gateway` | 1 | Outbound internet for private subnets |
| `aws_route_table` | 2 | Public (→ IGW), Private (→ NAT) |
| `aws_route_table_association` | 4 | Wire each subnet to its route table |

### Key implementation patterns

**`count` for repeated resources.** Public and private subnets, plus their route table associations, all use `count = length(var.X_subnet_cidrs)`. Inside, `var.X_subnet_cidrs[count.index]` and `var.availability_zones[count.index]` use the same index — so list ordering must match between CIDRs and AZs.

**`map_public_ip_on_launch = true`** on public subnets only. Strictly speaking the route table is what makes a subnet public, but this convenience setting means EC2 launches automatically get a public IP.

**`depends_on = [aws_internet_gateway.main]`** on the EIP and NAT Gateway. Terraform usually figures out dependencies from references, but here there's no direct reference between EIP and IGW. Explicit dependency added because allocating an EIP that'll be used through an IGW before the IGW exists has occasionally caused issues. Belt and braces.

**Module-level `versions.tf`.** Initially the module had no provider constraint, so its lock file resolved to AWS provider 6.44.0 while the root pinned 5.x. Two different lock files in the same project pinning two different major versions would have failed at apply. Fixed by adding `versions.tf` to the module mirroring the root constraint. This is why every module in the wild declares its own `required_providers`.

### Outputs surfaced

`vpc_id`, `vpc_cidr`, `public_subnet_ids` (splat: `aws_subnet.public[*].id`), `private_subnet_ids`, `internet_gateway_id`, `nat_gateway_id`. Six values — the ones other modules and CI/CD might need. Internal route tables and EIP are not exposed.

---

## Step 5 — Security module

The module that was missing entirely from the reference build. Net-new code, three SGs in a least-privilege chain.

### Resources created (10 total)

| Resource | Count | Purpose |
|---|---|---|
| `aws_security_group` | 3 | Frontend, backend, database |
| `aws_security_group_rule` (ingress) | 4 | 80+443 to frontend, 8080 to backend, 5432 to database |
| `aws_security_group_rule` (egress) | 3 | All-outbound from each tier (explicit) |

### The SG-to-SG chain

```
internet ──▶ frontend-sg (80, 443 from 0.0.0.0/0)
                │
                └──▶ backend-sg (8080, only from frontend-sg via source_security_group_id)
                          │
                          └──▶ database-sg (5432, only from backend-sg)
```

The critical line in HCL:

```hcl
source_security_group_id = aws_security_group.frontend.id
```

The backend's ingress doesn't say "allow from these IPs" — it says "allow from anything that's a member of the frontend security group." If a pod has the frontend SG attached, it can reach the backend on 8080. If not, it can't. New instances joining a tier inherit access automatically; no CIDR maintenance.

### Why separate `aws_security_group_rule` resources, not inline blocks

Two reasons:
1. **No circular-dependency risk** if bidirectional rules are ever added — inline rules can deadlock at apply.
2. **Cleaner diffs** — adding a rule is a single resource change.

Trade-off: can't mix inline and separate on the same SG. We picked separate.

### Egress rules — explicit

Default SG behaviour in AWS is allow-all-out, so the egress rules are technically redundant. Made them explicit because reading the module standalone, the egress posture is now obvious without relying on AWS defaults.

---

## Step 6 — ECR module

Smallest module in the project. Two repositories, two lifecycle policies.

### Resources created (4 total)

| Resource | Count | Purpose |
|---|---|---|
| `aws_ecr_repository` | 2 | One per image — frontend and backend |
| `aws_ecr_lifecycle_policy` | 2 | Keep last 10 tagged + expire untagged after 7 days |

### Key implementation patterns

**`for_each = toset(var.repository_names)`.** First time using `for_each` rather than `count`. Difference matters: `count` keys by index, so removing an item shifts everything's index and forces unnecessary recreations. `for_each` keys by name, so removing one repo only affects that one. Rule of thumb: `count` for "N copies of the same thing", `for_each` for "one per named thing" — and you almost always want the second.

**`jsonencode()` for the lifecycle policy.** AWS expects the policy as JSON, but writing it as HCL and converting via `jsonencode` lets Terraform validate the structure at plan time. Cleaner than embedding JSON as a string.

**`image_tag_mutability = MUTABLE`** for dev — `:latest` overwritable. Validation block restricts to only `MUTABLE` or `IMMUTABLE`. Production uses `IMMUTABLE` + SHA tags for traceability.

**Image scanning enabled (basic tier).** Free CVE scanning on every push. Enhanced scanning via Inspector available for language-level CVEs but costs extra.

### Outputs use `for` expressions

```hcl
value = { for name, repo in aws_ecr_repository.this : name => repo.repository_url }
```

Builds a map: keys are repo names, values are URLs. Consumers get:

```
{
  "multi-tier-frontend" = "340752829546.dkr.ecr.eu-west-1.amazonaws.com/multi-tier-frontend"
  "multi-tier-backend"  = "340752829546.dkr.ecr.eu-west-1.amazonaws.com/multi-tier-backend"
}
```

CI/CD pipelines use these URLs as `docker push` targets.

### Variable name flow — where the repo names actually live

A common point of confusion: the `multi-tier-frontend` and `multi-tier-backend` names aren't defined inside `modules/ecr/` at all. The module is generic — it takes whatever names the caller passes in. The names cascade through four layers:

```
terraform.tfvars  →  root variables.tf (default: ["multi-tier-frontend", "multi-tier-backend"])
                  →  root main.tf      (module "ecr" { repository_names = var.ecr_repository_names })
                  →  modules/ecr/variables.tf  (variable "repository_names" — no default)
                  →  modules/ecr/main.tf       (for_each over the list)
```

This is how a generic module stays reusable — it never hardcodes project-specific values. Single source of truth at the root.

---

## Step 7 — Root composition (main.tf + outputs.tf)

Where the modules wire together. Critical principle: **root composes, modules implement.** No `resource` blocks at root — only `module` blocks.

### main.tf

```hcl
module "vpc" {
  source = "./modules/vpc"
  # ... pass through all required variables
}

module "security" {
  source = "./modules/security"
  vpc_id = module.vpc.vpc_id    # <-- this is the wire
  # ...
}

module "ecr" {
  source = "./modules/ecr"
  # ... independent of the others
}
```

The `vpc_id = module.vpc.vpc_id` reference is the entire dependency graph. Terraform reads that line, knows security depends on VPC, and orders the apply correctly. No `depends_on` block needed. ECR has no module references → Terraform provisions it in parallel with VPC.

### outputs.tf

Nine root outputs re-exporting key values from each module: `vpc_id`, subnet IDs, security group IDs, ECR URLs and ARNs, registry ID. These show up in `terraform output` and are what CI/CD jobs read.

Internal values (route table IDs, EIP, NAT ID) are not re-exported — they're implementation details, not part of the public API.

### First plan against AWS

After init, `terraform plan` produced:

```
Plan: 28 to add, 0 to change, 0 to destroy.
```

Plan stopped here — no `apply` in Module 1. Verifies the whole composition resolves cleanly and AWS accepts the proposed state.

---

## Step 8 — Remote state backend

The final wire. Until this step, all init runs used `-backend=false`, meaning Terraform never created or read any state file at all. Step 8 configures the S3 backend pointing at the bucket and DynamoDB table from Step 1.

### backend.tf

```hcl
terraform {
  backend "s3" {
    bucket         = "multi-tier-app-tfstate-340752829546"
    key            = "project-001/terraform.tfstate"
    region         = "eu-west-1"
    encrypt        = true
    dynamodb_table = "multi-tier-app-tf-locks"
  }
}
```

| Field | Purpose |
|---|---|
| `bucket` | The S3 bucket created in Step 1 (literal — the backend block can't use variables) |
| `key` | Path within the bucket. Convention: `<project>/<env>/terraform.tfstate`. Multi-environment setups use the key to isolate state per environment |
| `region` | Must match where the bucket was created |
| `encrypt` | SSE on state file uploads — always `true`, state contains sensitive data |
| `dynamodb_table` | Locking table from Step 1. Lock acquired before plan/apply, released after |

**The backend block can't use variables.** Long-standing Terraform constraint: backend resolves before variable parsing happens during init. `terraform init -backend-config="bucket=..."` is the workaround for environment-specific backends; for our single-env project, hardcoding is fine.

### The init that wired the backend

```bash
rm -rf .terraform        # wipe artefacts from previous backend-skipped inits
terraform init           # without -backend=false this time
```

Output included `Successfully configured the backend "s3"!` — confirming Terraform tested:
- Bucket exists and is accessible
- IAM permissions sufficient for `s3:GetObject` / `s3:PutObject`
- DynamoDB table is reachable and Terraform can write/release lock entries

### Confirmed end-to-end

```bash
terraform plan
```

- `Acquiring state lock. This may take a few moments...` — DynamoDB lock works
- `Plan: 28 to add, 0 to change, 0 to destroy.` — same as Step 7's plan, sourced from S3 state
- Lock auto-released when plan finished

State file in S3 is empty until the first `apply` runs — `plan` is read-only and writes nothing. The backend is verifiably wired regardless: the success of the lock acquisition + plan reading state + plan releasing the lock all confirm the end-to-end flow.

---

## Interview questions covered

Eight questions from `Interview-Prep-Combined.md` addressed across this module's video. Slides created for the visually-rich ones:

| ID | Topic | Step | Slides |
|---|---|---|---|
| tf-002 | Terraform state, S3+DynamoDB remote backend, locking | 1 (DynamoDB lock table) | text-only |
| tf-001 | Terraform fundamentals — IaC, providers, plan/apply, vs CloudFormation | 2 (providers.tf) | text-only |
| tf-004 | Variables, validation, locals, tfvars precedence | 3 (variables.tf) | text-only |
| tf-003 (anatomy) | Modules — what they are, structure, sources | 4 (first module) | text-only |
| aws-002 | Public vs private subnets, route-table-based distinction | 4 (subnets) | text-only |
| aws-014 | IGW vs NAT Gateway vs NAT Instance, cost story | 4 (NAT resource) | ✅ `interview-slides/aws-014-igw-vs-nat.pptx` |
| aws-003 | NACLs vs Security Groups, SG-to-SG references | 5 (security module) | ✅ `interview-slides/aws-003-nacl-vs-sg.pptx` |
| docker-009 | ECR auth, lifecycle policies, MUTABLE vs IMMUTABLE | 6 (ECR module) | ✅ `interview-slides/docker-009-ecr.pptx` |
| tf-003 (composition) | Module composition, implicit dependency graph | 7 (root main.tf) | ✅ `interview-slides/tf-003-modules.pptx` |

---

## Project vs Real Life

What we did vs what production looks like:

| Project | Production |
|---|---|
| Single NAT Gateway in AZ-a | One NAT per AZ for HA — if AZ-a fails, AZ-b loses egress |
| Custom-written VPC module | `terraform-aws-modules/vpc/aws` — battle-tested, handles edge cases |
| ECR `MUTABLE` tags | `IMMUTABLE` tags + commit SHA — bulletproof traceability |
| ECR basic scanning | Enhanced scanning via Inspector — language-level CVEs (npm, pip) |
| No VPC Flow Logs | Enabled to S3 or CloudWatch for forensics |
| No VPC endpoints | At minimum S3 Gateway endpoint — slashes NAT data-processing bills |
| DB subnets share NAT route with app | Dedicated DB subnet group, no NAT route at all (Postgres doesn't need internet) |
| Database SG egress all-out | Narrow to Secrets Manager + RDS endpoints only |
| Single environment, single state file | Per-env state files (`project-001/dev`, `project-001/prod`) for blast-radius isolation |
| Lock table not encrypted | KMS encryption on the lock table for sensitive lock metadata |
| ECR repo per project | Cross-account ECR with repository policies for shared registries |

---

## Key concepts learned

- **Bootstrap order matters.** S3 + DynamoDB must exist before `terraform init` reads `backend.tf`. AWS CLI bootstraps; Terraform manages everything afterward.
- **Validation pays back in interviews and in real debugging.** Catch bad inputs at plan time, not three minutes into apply.
- **Modules are for reusability, not for showing off.** Default to community modules for VPC/EKS/RDS where they fit; write internal modules for company-specific patterns; keep root configs small.
- **`for_each` over `count`** for "one per named thing" — removing items doesn't shift indexes and force recreations.
- **Module-level `versions.tf` matters.** Without it, modules pull whatever provider's latest at init, leading to lock-file drift between root and modules. Match the root's pin in every module.
- **SG-to-SG references > CIDR rules.** Membership tracking, not IP tracking. Add an instance to a tier → it inherits access automatically.
- **Composition through references = automatic dependency graph.** No `depends_on` needed when one module references another's output.
- **Plan is read-only, apply writes state.** A successful plan against an empty backend means the wiring works; state lands in S3 only on apply.
- **Pin everything that can be pinned.** Terraform CLI version, provider major version, lock-file provider hashes. Reproducibility is non-negotiable.

---

## Cleanup

> ⚠️ **IMPORTANT — Resources still in AWS after Module 1:**
>
> The S3 state bucket and DynamoDB lock table from Step 1 are still in AWS and incurring (very small) costs. Module 1 stopped at `plan`, so **none of the 28 resources from the plan have been created** — those only land when Module 4 runs the first `terraform apply`.
>
> **Do not run `terraform destroy` after Module 1** — there's nothing to destroy yet (nothing was applied). The state bucket and lock table will be needed by every subsequent module.

For the entire project series, complete cleanup happens at the end of Module 10:

```bash
# After the project is complete and recordings are done:
cd ~/cloud-engineer-labs/projects/project-001-build-multi-tier-app/solution/terraform

terraform destroy   # tears down the 28 resources

# Then manually delete the bootstrap resources:
aws s3 rm s3://multi-tier-app-tfstate-340752829546 --recursive
aws s3api delete-bucket --bucket multi-tier-app-tfstate-340752829546
aws dynamodb delete-table --table-name multi-tier-app-tf-locks
```

For the moment, the only ongoing cost is:
- S3: state file bytes × storage tier × time = pennies/month
- DynamoDB: PAY_PER_REQUEST mode, basically zero when idle

Total Module 1 ongoing cost: **<$0.10/month**.
