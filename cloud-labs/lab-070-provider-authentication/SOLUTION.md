# Solution Walkthrough — Provider Authentication

## The Problem

Terraform init and plan are failing because the provider configuration has **three bugs**:

1. **Invalid AWS region** — the primary provider uses `region = "eu-west-99"`, which doesn't exist. AWS regions have specific names like `eu-west-1`, `eu-west-2`, `us-east-1`, etc.
2. **Duplicate provider without alias** — there are two `provider "aws"` blocks, but the second one doesn't have an `alias`. Terraform doesn't allow two providers of the same type without aliases to differentiate them.
3. **Resource references non-existent alias** — the S3 backup bucket uses `provider = aws.backup_region`, but no provider has `alias = "backup_region"`. The alias on the second provider must match what the resource references.

## Thought Process

When Terraform fails at the provider level, an experienced engineer checks:

1. **Region validity** — is the region name a real AWS region? Common EU regions: `eu-west-1` (Ireland), `eu-west-2` (London), `eu-central-1` (Frankfurt).
2. **Provider aliases** — multiple providers of the same type need aliases. Without aliases, Terraform can't distinguish them.
3. **Resource-to-provider mapping** — when a resource uses `provider = aws.something`, that alias must exist on a provider block.

## Step-by-Step Solution

### Step 1: Fix Bug 1 — Use a valid AWS region

```hcl
# BROKEN
provider "aws" {
  region = "eu-west-99"    # Not a real region!
}

# FIXED
provider "aws" {
  region = "eu-west-2"     # London region
}
```

**Why this matters:** Terraform validates the region with AWS during `terraform init`. An invalid region causes authentication to fail immediately because Terraform can't construct valid API endpoints.

### Step 2: Fix Bug 2 — Add alias to second provider

```hcl
# BROKEN — two providers without alias
provider "aws" {
  region = "us-east-1"
}

# FIXED — add alias
provider "aws" {
  alias  = "backup_region"
  region = "us-east-1"
}
```

**Why this matters:** Terraform uses the default (un-aliased) provider for resources that don't specify a provider. For resources that need a different region or account, you use an aliased provider and reference it with `provider = aws.alias_name`. Without the alias, Terraform sees a duplicate provider definition and errors.

### Step 3: Fix Bug 3 — Resource references match the alias

The resource already references `aws.backup_region`, which now matches the alias we added:

```hcl
resource "aws_s3_bucket" "backup" {
  provider = aws.backup_region    # Matches alias = "backup_region"
  bucket   = "backup-data-bucket"
}
```

### Step 4: The complete fixed main.tf

```hcl
provider "aws" {
  region = "eu-west-2"
}

provider "aws" {
  alias  = "backup_region"
  region = "us-east-1"
}

resource "aws_s3_bucket" "backup" {
  provider = aws.backup_region
  bucket   = "backup-data-bucket"
}

resource "aws_s3_bucket" "primary" {
  bucket = "primary-data-bucket"
}
```

### Step 5: Validate

```bash
terraform init
terraform validate
terraform plan
```

**What this does:** Initializes both providers (eu-west-2 and us-east-1), validates the configuration, and plans the resources. The primary bucket is created in eu-west-2, the backup bucket in us-east-1.

## Docker Lab vs Real Life

- **Credential chain:** In production, AWS credentials are resolved through the credential chain: environment variables → shared credentials file → IAM instance profile → ECS task role → SSO. Never hardcode credentials in provider blocks.
- **Assume role:** Production Terraform often uses `assume_role` in the provider block to switch to a specific IAM role for deployments. This provides better audit trails and permission boundaries.
- **Multiple accounts:** Real multi-account setups use provider aliases with different `assume_role` configurations to deploy resources across AWS accounts (e.g., shared services, production, staging).
- **Required provider versions:** Production configurations pin provider versions: `required_providers { aws = { version = "~> 5.0" } }` to prevent breaking changes from provider updates.
- **Backend authentication:** The Terraform backend (S3 state storage) also needs valid credentials. Backend authentication is separate from provider authentication.

## Key Concepts Learned

- **AWS regions are fixed names** — there's no `eu-west-99`. Always use valid region codes. Run `aws ec2 describe-regions` to list all available regions.
- **Provider aliases enable multi-region deployments** — the default provider (no alias) handles most resources. Aliased providers handle resources in other regions or accounts.
- **`provider = aws.alias_name` links resources to specific providers** — without this, resources use the default provider. The alias name must match exactly.
- **Terraform init validates provider configuration** — invalid regions or credentials are caught during init, not plan. Always run init first after changing provider blocks.

## Common Mistakes

- **Typos in region names** — `eu-west-2` vs `eu-west-02` vs `eu-west-99`. There's no autocomplete or fuzzy matching — it must be exact.
- **Forgetting the alias on the second provider** — Terraform doesn't allow two providers of the same type without aliases. The error message "duplicate provider configuration" tells you exactly what's wrong.
- **Alias mismatch between provider and resource** — if the provider has `alias = "backup"` but the resource uses `provider = aws.backup_region`, they don't match. The names must be identical.
- **Hardcoding credentials in provider blocks** — never put `access_key` and `secret_key` in Terraform files. Use environment variables, IAM roles, or AWS SSO.
- **Not re-running `terraform init` after changing providers** — adding, removing, or changing provider configurations requires re-running init to reinitialize the provider plugins.
