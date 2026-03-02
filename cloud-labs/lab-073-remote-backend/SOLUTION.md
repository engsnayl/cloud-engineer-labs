# Solution Walkthrough — Remote Backend Configuration

## The Problem

The team has been running Terraform with local state files, and a colleague's laptop just died — taking the only copy of the production state with it. The state is gone, meaning Terraform has no record of what infrastructure it manages. The task is to set up a proper remote backend to prevent this from happening again. There are **three issues**:

1. **No backend configured** — state is stored locally by default. If the local file is lost, Terraform loses track of all managed resources.
2. **Missing DynamoDB table for state locking** — without locking, two engineers running `terraform apply` simultaneously can corrupt the state. The DynamoDB table resource is commented out.
3. **Missing server-side encryption** — the state file contains sensitive information (resource IDs, sometimes passwords). It should be encrypted at rest.

## Thought Process

When setting up a Terraform remote backend, an experienced engineer ensures:

1. **S3 bucket with versioning** — stores the state file. Versioning allows recovery from accidental overwrites or corruption.
2. **DynamoDB table for locking** — prevents concurrent state modifications. The hash key must be `LockID` (a Terraform convention).
3. **Encryption** — server-side encryption protects sensitive data in the state file at rest.
4. **Backend configuration** — the `terraform { backend "s3" { } }` block tells Terraform where to store state.
5. **State migration** — `terraform init -migrate-state` moves existing local state to the remote backend.

## Step-by-Step Solution

### Step 1: Uncomment the DynamoDB table

```hcl
resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
```

**Why this matters:** The DynamoDB table provides state locking. When someone runs `terraform apply`, Terraform creates a lock entry in this table. If another person tries to run apply at the same time, Terraform sees the lock and waits (or errors), preventing concurrent modifications that could corrupt the state. The hash key **must** be `LockID` — this is a hard requirement from Terraform's S3 backend.

### Step 2: Add server-side encryption to the state bucket

```hcl
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}
```

**Why this matters:** Terraform state files can contain sensitive data — resource IDs, IP addresses, and sometimes even passwords or tokens. Encrypting the bucket ensures this data is protected at rest. `aws:kms` uses AWS Key Management Service for encryption; `AES256` is the simpler alternative.

### Step 3: Add public access block to the state bucket

```hcl
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

**Why this matters:** The state file should never be publicly accessible. This block prevents any accidental public access configuration.

### Step 4: Configure the backend block

```hcl
terraform {
  backend "s3" {
    bucket         = "terraform-state-lab"
    key            = "production/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

**Why this matters:** This tells Terraform to store state in S3 instead of locally:
- **`bucket`** — the S3 bucket name
- **`key`** — the path within the bucket (allows multiple state files in one bucket)
- **`region`** — the bucket's region
- **`dynamodb_table`** — enables state locking
- **`encrypt`** — ensures the state file is encrypted when stored

**Important note:** The backend infrastructure (S3 bucket, DynamoDB table) must exist before you configure the backend. This creates a chicken-and-egg problem — you typically create the backend infrastructure with a separate Terraform configuration that uses local state, then configure other projects to use the remote backend.

### Step 5: Initialize with state migration

```bash
terraform init -migrate-state
```

**What this does:** Moves the existing local state file to the S3 backend. Terraform downloads the provider, detects the backend change, and asks to copy the existing state to the new backend. Answer "yes" to migrate.

### Step 6: Validate

```bash
terraform validate
terraform plan
```

## Docker Lab vs Real Life

- **Chicken-and-egg problem:** In production, the backend infrastructure (S3 bucket + DynamoDB table) is created by a separate "bootstrap" Terraform configuration that uses local state. All other Terraform projects then reference this backend.
- **Terraform Cloud / Enterprise:** Many teams use Terraform Cloud instead of S3 for state management. It provides state storage, locking, run history, and team collaboration out of the box.
- **Cross-account state:** In multi-account setups, the state bucket is often in a dedicated "management" account. Other accounts assume a role to read/write state.
- **State file backups:** S3 versioning provides automatic backups. If someone corrupts the state, you can restore a previous version from the S3 version history.
- **Partial backend configuration:** In CI/CD pipelines, backend configuration is often split between the `.tf` file and `-backend-config` flags: `terraform init -backend-config="bucket=my-bucket"`. This allows different backends per environment without changing code.

## Key Concepts Learned

- **Remote state prevents state loss** — local state files are fragile. Remote state in S3 is durable, versioned, and accessible to the whole team.
- **DynamoDB provides state locking** — prevents concurrent modifications. The table must have `LockID` as the hash key.
- **`terraform init -migrate-state` moves state** — use this when switching from local to remote (or between backends). Terraform copies the state to the new location.
- **Backend infrastructure must exist first** — you can't use an S3 backend that doesn't exist yet. Create the bucket and table first (with local state), then configure the backend.
- **Encrypt state files** — state can contain sensitive data. Enable encryption on both the S3 bucket and the backend configuration.

## Common Mistakes

- **Creating the backend and using it in the same configuration** — the S3 bucket and DynamoDB table must exist before the backend block references them. Use a separate bootstrap configuration.
- **Forgetting `-migrate-state` when changing backends** — without migration, Terraform starts with an empty state and tries to create duplicate resources.
- **Wrong DynamoDB hash key** — the hash key must be `LockID` (capital L, capital I, capital D). Any other name causes locking to fail silently.
- **Not enabling S3 versioning** — without versioning, an accidental state overwrite is permanent. Versioning provides a safety net to restore previous state versions.
- **Not restricting bucket access** — the state bucket should only be accessible to the Terraform runners and administrators. Use bucket policies and IAM to restrict access.
