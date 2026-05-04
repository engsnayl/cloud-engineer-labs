# Module 1 — Terraform: Networking, Security, ECR

## TLDR

This module builds the Terraform layer for the capstone — the AWS infrastructure that supports the three-tier application. By the end we have:

- A modular Terraform configuration in `solution/terraform/` with three child modules: `vpc/`, `security/`, `ecr/`
- A VPC with public + private subnets across two AZs in `eu-west-1`
- Three security groups in a least-privilege chain (frontend → backend → database)
- Two ECR repositories (frontend, backend) with lifecycle policies
- Remote state in S3 with DynamoDB locking

We stop at a successful `terraform plan`. The only AWS resources actually created during this module are the S3 state bucket and DynamoDB lock table — bootstrapped via the AWS CLI before Terraform is initialised.

**Skills demonstrated:** Terraform modules, S3 remote state, DynamoDB state locking, VPC design (multi-AZ, public/private subnets, NAT gateway), least-privilege security groups with chained source references, ECR with lifecycle policies, provider version pinning.

---

## Pre-flight checks

Three things to confirm before touching anything:

```bash
cd ~/cloud-engineer-labs
git status                          # working tree clean
aws sts get-caller-identity         # right user, right account
aws configure get region            # eu-west-1
terraform version                   # 1.10.5 (1.15.x is out, but 1.10.5 is fine for this project)
```

Confirmed:
- Repo clean, on `main`, in sync with origin
- IAM user `StephenNaylor`, account `340752829546`
- Region `eu-west-1`
- Terraform v1.10.5 on `linux_arm64`

---

## Design decisions

Locked in before writing any code, so we're not making them under pressure mid-build.

### Networking

| Decision | Value | Reasoning |
|---|---|---|
| VPC CIDR | `10.0.0.0/16` | Standard private range, 65k addresses |
| AZs | `eu-west-1a`, `eu-west-1b` | Two AZs satisfies multi-AZ; three would mean an extra NAT |
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

Critical: the chain uses **source security group references**, not CIDR blocks. Rules track membership, not IPs. A new instance added to the backend tier automatically inherits database access.

These SGs are for future EC2/RDS use. The current K3s deployment runs on the Pi and doesn't consume them. They exist so the Terraform layer is complete and interview-defensible, and so the architecture is ready to migrate to EC2/EKS.

### ECR

| Decision | Value | Reasoning |
|---|---|---|
| Repositories | `multi-tier-frontend`, `multi-tier-backend` | One per image |
| Tag mutability | `MUTABLE` | Need `:latest` to be overwritable for dev. Production would use `IMMUTABLE` + SHA tags only |
| Scan on push | `true` | Free CVE scanning |
| Lifecycle | Keep last 10 images; expire untagged after 7 days | Stops registry bloat; preserves rollback |

### Remote state

| Decision | Value | Reasoning |
|---|---|---|
| Bucket | `multi-tier-app-tfstate-340752829546` | `<project>-tfstate-<account-id>`; account ID guarantees global uniqueness |
| Versioning | Enabled | State files are precious — you will want to roll back one day |
| Public access | Blocked at all four levels | State contains secrets |
| Lock table | `multi-tier-app-tf-locks` | DynamoDB |
| Lock partition key | `LockID` (string) | **Hardcoded by Terraform — must be exactly this** |
| Billing | `PAY_PER_REQUEST` | Cents/month vs provisioned mode's dollars |

---

## Build order

Bottom-up. Each layer verifiable before the next:

1. Bootstrap S3 + DynamoDB via AWS CLI
2. `solution/terraform/` skeleton + `providers.tf`
3. `variables.tf` + `terraform.tfvars.example`
4. `modules/vpc/` (built fresh, not copied from reference)
5. `modules/security/` (built fresh)
6. `modules/ecr/` (built fresh)
7. Root `main.tf` — wire modules together
8. Root `outputs.tf`
9. `backend.tf`
10. `terraform init && plan`

## Interview questions covered

This module addresses the following interview questions from `Interview-Prep-Combined.md`. Each is logged with the angle it was covered from, so coverage is trackable across the 11-module series.

| ID | Topic | Covered in step | Angle |
|---|---|---|---|
| tf-002 | State, remote state, S3+DynamoDB, locking | Step 1d (sidebar) | Delivered the full interview answer at the moment of creating the DynamoDB lock table — covered why state, why remote, why S3+DynamoDB specifically, and the `LockID` hardcoded-name gotcha |
| tf-001 | Terraform fundamentals — IaC, providers, plan/apply, vs CloudFormation/CDK | Step 2b (sidebar) | Delivered the full fundamentals answer while explaining `providers.tf` — covered HCL, provider model, state, plan-as-safety-mechanism, and when not to use Terraform |

---

## Step 1 — Bootstrap the remote state

Terraform's S3 backend needs the bucket and lock table to exist *before* `terraform init` reads `backend.tf`. We bootstrap these with the AWS CLI rather than Terraform itself — chicken-and-egg.

### 1a. Set bootstrap variables

```bash
export AWS_REGION=eu-west-1
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export TF_STATE_BUCKET="multi-tier-app-tfstate-${AWS_ACCOUNT_ID}"
export TF_LOCK_TABLE="multi-tier-app-tf-locks"
```

The bucket name is composed as `<project>-tfstate-<account-id>`. The account ID guarantees global uniqueness in S3's flat namespace — no two accounts share an ID. The account ID itself is fetched from `aws sts get-caller-identity` rather than hardcoded, so the same script works regardless of which AWS profile is active.

Verified output:

```
Region:  eu-west-1
Account: 340752829546
Bucket:  multi-tier-app-tfstate-340752829546
Table:   multi-tier-app-tf-locks
```

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

### Why this is in the AWS CLI, not Terraform

The S3 backend is initialised on `terraform init`, which reads `backend.tf` and immediately tries to access the bucket. If the bucket doesn't exist yet, init fails. You _can_ bootstrap with local state and migrate, but it adds steps and creates a "this code only works in a specific order" footgun. Two CLI commands per resource is cleaner — and these two resources never need to change again.

---

## Step 2 — Terraform skeleton + providers.tf

### 2a. Create the directory tree

```bash
cd solution
mkdir -p terraform/modules/{vpc,security,ecr}
```

Final layout (so far):

```
solution/terraform/
└── modules/
    ├── vpc/
    ├── security/
    └── ecr/
```

The `solution/` vs `reference/` separation is deliberate. `reference/` is read-only — Claude Code's full reference build, used for sanity-checking but never `terraform apply`'d. `solution/` is where this build lives.

### 2b. Create providers.tf

```bash
vi terraform/providers.tf
```

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
| `terraform { required_version }` | Pins the Terraform CLI version. Prevents anyone running this with an incompatible CLI (e.g. 0.12, or a future 2.0). HCL syntax and state format have changed across major versions — pinning means predictable behaviour for anyone who clones the repo. |
| `required_providers { aws }` | Declares the AWS provider as a dependency, pinned to the 5.70 series. |
| `version = "~> 5.70"` | **Pessimistic version constraint**: 5.70 or later, but only within the 5.x major series. AWS provider major versions occasionally have breaking changes; pinning the major prevents silent upgrades into broken configs. |
| `provider "aws" { region }` | Pulls region from a root variable so the same code works for any region without editing. |
| `default_tags` | Tags applied to every taggable resource Terraform creates. `ManagedBy = "Terraform"` is especially valuable — anyone seeing a resource in the AWS console knows immediately not to click-modify it. |

### Why providers come before everything else

Every `.tf` file depends on which provider plugins are loaded. You can't write `resource "aws_vpc"` without the AWS provider being declared and pinned. Providers are the foundation — modules, variables, root composition all build on top.
