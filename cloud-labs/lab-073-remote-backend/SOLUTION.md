# Lab 073 — Remote Backend Configuration
## Solution Walkthrough

---

## Plain-English TLDR

Imagine you keep your project notes in a notebook on your desk. If your desk catches fire, the notes are gone — and nobody else on your team ever had a copy. That's what happened here: Terraform was storing its "memory" of what infrastructure it manages (called **state**) in a file on one person's laptop, and that laptop died.

This lab fixes three things:

1. **Move the state file off the laptop and into a shared, durable location** (an S3 bucket in AWS).
2. **Add a locking mechanism** so that if two engineers run Terraform at the same time, they don't corrupt that shared file (a DynamoDB table acts as a "door lock").
3. **Encrypt the state file**, because it can contain sensitive information like resource IDs, IP addresses, and sometimes even passwords.

By the end of this lab, the state file lives in S3, it's locked during operations, and it's encrypted at rest.

---

## Before You Start — Run the Setup Script

This lab requires some starting conditions to be in place before you begin. Specifically, the S3 bucket needs to already exist (representing infrastructure that was set up before the laptop died), and a local `terraform.tfstate` file needs to be present (representing the state that was living on that laptop).

A setup script handles all of this for you.

```bash
# From the lab directory:
chmod +x setup.sh
./setup.sh
```

**What the setup script does:**

| Action | Why |
|--------|-----|
| Creates the S3 bucket (`terraform-state-340752829546`) via AWS CLI | The bucket exists in AWS but has no backend configured — your job is to wire Terraform up to it |
| Enables versioning on the bucket | Versioning is already considered best practice; the bucket is "pre-configured" in this regard |
| Drops a `terraform.tfstate` stub file into the lab directory | Simulates the local state file that was on the lost laptop — this is what you'll migrate to S3 |

**What the setup script does NOT do:**

- Create the DynamoDB table — that's your job (it's commented out in `main.tf`)
- Configure the backend block — that's your job
- Run `terraform init` or `terraform apply` — you do that during the lab

Once the script completes, the scene is set. You're the engineer picking up this ticket.

---

## The Ticket

> **Incident summary:** A colleague's laptop was destroyed. It contained the only copy of the Terraform state file for the production environment. The team no longer has a record of what infrastructure Terraform is managing. Any future `terraform apply` would try to create everything from scratch, resulting in duplicate resources and potential outage.
>
> **Your task:** Configure a remote backend so state is stored in S3 with locking and encryption enabled.

---

## What You're Looking At — `main.tf` Line by Line

Before touching anything, read the file in full. Here is exactly what the starting `main.tf` contains, and what each part means.

---

### Block 1 — Provider

```hcl
provider "aws" {
  region = "eu-west-2"
}
```

| Line | What it means |
|------|--------------|
| `provider "aws"` | Tells Terraform to use the AWS provider plugin — this is what gives Terraform the ability to create AWS resources |
| `region = "eu-west-2"` | All resources created by this configuration will default to the London region unless explicitly overridden |

**AS-IS:** This is correct and complete. No changes needed here.

---

### Block 2 — Backend (commented out)

```hcl
# TASK: Add a terraform backend block for S3
# terraform {
#   backend "s3" {
#     bucket         = "terraform-state-ACCOUNT_ID"
#     key            = "production/terraform.tfstate"
#     region         = "eu-west-2"
#     dynamodb_table = "terraform-locks"
#     encrypt        = true
#   }
# }
```

**AS-IS:** The entire `terraform {}` backend block is commented out. This means Terraform has no backend configured. Without a backend block, Terraform writes state to a local file called `terraform.tfstate` in the working directory. That file only exists on the machine running Terraform — if that machine is lost, the state is gone.

**TO-BE:** Uncomment this block and correct it. The `bucket` value uses a placeholder (`terraform-state-ACCOUNT_ID`) — replace it with the actual bucket name (`terraform-state-340752829546`). The corrected block:

```hcl
terraform {
  backend "s3" {
    bucket         = "terraform-state-340752829546"
    key            = "production/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

| Argument | What it does |
|----------|-------------|
| `backend "s3"` | Tells Terraform to use S3 as its state storage backend |
| `bucket` | The name of the S3 bucket where the state file will live |
| `key` | The path inside the bucket for the state file — using a path like `production/terraform.tfstate` means you can store multiple environments' state in one bucket |
| `region` | The AWS region the S3 bucket lives in |
| `dynamodb_table` | The DynamoDB table to use for state locking — must match the table name exactly |
| `encrypt` | Instructs Terraform to encrypt the state file when writing it to S3 |

---

### Block 3 — S3 Bucket

```hcl
resource "aws_s3_bucket" "terraform_state" {
  bucket = "terraform-state-340752829546"
}
```

| Line | What it means |
|------|--------------|
| `resource "aws_s3_bucket"` | Creates an S3 bucket in AWS |
| `"terraform_state"` | The local Terraform name for this resource — used to reference it elsewhere in the config as `aws_s3_bucket.terraform_state` |
| `bucket = "terraform-state-340752829546"` | The actual bucket name in AWS — must be globally unique across all AWS accounts |

**AS-IS:** The bucket exists but has no encryption and no public access restrictions. It's a bare bucket.

**TO-BE:** Two additional resources need to be added that reference this bucket (encryption and public access block — covered in Blocks 5 and 6 below).

---

### Block 4 — S3 Bucket Versioning

```hcl
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}
```

| Line | What it means |
|------|--------------|
| `resource "aws_s3_bucket_versioning"` | A separate resource that controls versioning on an existing S3 bucket — in AWS provider v4+, bucket settings are split into their own resource types rather than nested inside the bucket resource |
| `bucket = aws_s3_bucket.terraform_state.id` | References the bucket created in Block 3 by its Terraform resource ID — `.id` resolves to the bucket name |
| `status = "Enabled"` | Turns versioning on — every time the state file is overwritten, S3 keeps the previous version, allowing rollback if the state is corrupted |

**AS-IS:** This is already correct and in place. Versioning is enabled. No changes needed here.

**TO-BE:** No change required.

---

### Block 5 — DynamoDB Table (commented out — missing)

```hcl
# Missing DynamoDB table for state locking
# resource "aws_dynamodb_table" "terraform_locks" {
#   name         = "terraform-locks"
#   billing_mode = "PAY_PER_REQUEST"
#   hash_key     = "LockID"
#   attribute {
#     name = "LockID"
#     type = "S"
#   }
# }
```

**AS-IS:** Entirely commented out. No locking table exists. Two engineers running `terraform apply` simultaneously would both read the same state, both calculate changes, and both write back — one overwriting the other, silently corrupting the state file.

**TO-BE:** Uncomment the entire block.

| Argument | What it does |
|----------|-------------|
| `resource "aws_dynamodb_table"` | Creates a DynamoDB table in AWS |
| `"terraform_locks"` | The local Terraform name for this resource |
| `name = "terraform-locks"` | The actual table name in AWS — must match exactly what the backend block references in `dynamodb_table` |
| `billing_mode = "PAY_PER_REQUEST"` | Pay per read/write operation rather than provisioning fixed capacity — cost-effective for a table that's only written to when someone runs Terraform |
| `hash_key = "LockID"` | The primary key of the DynamoDB table. **This must be exactly `LockID`** — this is a hard requirement from Terraform's S3 backend. Any other name causes locking to fail silently |
| `attribute { name = "LockID" type = "S" }` | Defines the `LockID` attribute as a String type (`"S"`) — DynamoDB requires all hash key attributes to be explicitly declared |

---

### Block 6 — Server-Side Encryption (commented out — missing)

```hcl
# Missing server-side encryption on state bucket
# resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
#   ...
# }
```

**AS-IS:** The comment acknowledges this is missing, but the full resource hasn't even been written — it's just a placeholder comment with `...`. You need to write this resource from scratch.

**TO-BE:** Add the complete resource:

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

| Argument | What it does |
|----------|-------------|
| `resource "aws_s3_bucket_server_side_encryption_configuration"` | A separate resource that controls encryption settings on an existing S3 bucket |
| `bucket = aws_s3_bucket.terraform_state.id` | References the same bucket from Block 3 |
| `rule` | Defines an encryption rule — a bucket can have multiple rules, but one is sufficient here |
| `apply_server_side_encryption_by_default` | Applies this encryption to every object written to the bucket unless explicitly overridden |
| `sse_algorithm = "aws:kms"` | Uses AWS Key Management Service for encryption. `AES256` is the simpler alternative using S3-managed keys — both are valid, `aws:kms` gives you more control and auditability |

---

### Block 7 — Public Access Block (not present — missing entirely)

**AS-IS:** This resource doesn't appear anywhere in `main.tf`, not even as a comment. The bucket has no hard restriction preventing it from being made public — an accidental bucket policy or ACL change could expose the state file.

**TO-BE:** Add this resource:

```hcl
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

| Argument | What it does |
|----------|-------------|
| `block_public_acls` | Blocks any PUT request that includes a public ACL — prevents objects being uploaded as public |
| `block_public_policy` | Blocks any bucket policy that grants public access |
| `ignore_public_acls` | Ignores any existing public ACLs already on objects in the bucket |
| `restrict_public_buckets` | Restricts access to the bucket owner and AWS services only, regardless of other settings |

Setting all four to `true` is the belt-and-braces approach — each covers a slightly different attack surface.

---

### Block 8 — VPC

```hcl
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "production-vpc" }
}
```

| Line | What it means |
|------|--------------|
| `resource "aws_vpc"` | Creates a Virtual Private Cloud — an isolated network in AWS |
| `"main"` | Local Terraform name for this resource |
| `cidr_block = "10.0.0.0/16"` | The IP address range for this VPC — `10.0.0.0/16` gives 65,536 available addresses |
| `tags = { Name = "production-vpc" }` | Labels the VPC in the AWS console for identification |

**AS-IS:** This represents the "production infrastructure" that Terraform is managing. It's the reason the state file matters — without state, Terraform has no record that this VPC exists and would try to create a duplicate.

**TO-BE:** No change required. This resource is here to give the state migration something meaningful to carry across.

---

### Summary — What Needs Changing

| Block | AS-IS | TO-BE |
|-------|-------|-------|
| Provider | ✅ Correct | No change |
| Backend block | ❌ Commented out | Uncomment and fix bucket name |
| S3 bucket | ⚠️ Exists but incomplete | No direct change — add encryption and public access block resources |
| S3 versioning | ✅ Correct | No change |
| DynamoDB table | ❌ Commented out | Uncomment |
| Encryption config | ❌ Missing entirely | Write from scratch |
| Public access block | ❌ Missing entirely | Write from scratch |
| VPC | ✅ Correct | No change |

---

## How to Approach This — The Engineer's Thought Process

When you pick up a Terraform-related ticket like this, you don't open `main.tf` straight away. You start by understanding the current state of the configuration and asking: *what is Terraform actually doing right now, and what is it missing?*

There are three questions to answer before you write a single line:

1. **Where is state being stored?** — Look for a `backend` block in `main.tf`. No backend block means local state.
2. **Is there anything preventing concurrent access corruption?** — Look for a DynamoDB table resource. Its absence means no locking.
3. **Is the state encrypted?** — Look at the S3 bucket resource for an encryption configuration.

Let's work through each of these in turn.

---

## Step 1 — Understand What You're Working With

### 1a. Review the configuration

Open `main.tf` and read through it top to bottom before touching anything. You're looking for:

- The `terraform {}` block — does it have a `backend` block inside it?
- Resources for `aws_s3_bucket` — is there a bucket for state?
- Resources for `aws_dynamodb_table` — is there a locking table? Is it commented out?
- Resources for `aws_s3_bucket_server_side_encryption_configuration` — is encryption configured?

```bash
cat main.tf
```

**What you should notice:**

- The `terraform {}` block has no `backend` block — state is being stored locally by default.
- There is an `aws_s3_bucket` resource for state storage, which is good — the bucket infrastructure exists.
- The `aws_dynamodb_table` resource is **commented out** — locking is not in place.
- There is no `aws_s3_bucket_server_side_encryption_configuration` resource — encryption is missing.
- There is no `aws_s3_bucket_public_access_block` resource — the bucket may be publicly accessible.

**Why does this matter?**

Without a backend block, Terraform writes state to `terraform.tfstate` in your working directory. This file only exists on the machine running Terraform. If that machine is lost, the state is lost with it.

### 1b. Confirm the current state storage location

```bash
terraform show
```

| Part | What it does |
|------|-------------|
| `terraform` | Invokes the Terraform CLI |
| `show` | Displays the current state — what Terraform believes is deployed |

If this outputs resources, there is an existing local state file. If it outputs nothing or errors, the state may already be lost. Either way, you're about to migrate it to a safe location.

---

## Step 2 — Fix the DynamoDB Table (Locking)

### What problem are you solving?

Without a DynamoDB table, two engineers can run `terraform apply` at the same time. Both read the same state, both calculate changes, both write back — and one overwrites the other's changes. This corrupts the state file silently. The DynamoDB table acts as a mutex (a "one person at a time" lock). When Terraform starts an operation, it writes a lock entry to the table. Anyone else who tries to start an operation sees the lock and waits.

### What to look for

The DynamoDB table resource is in `main.tf` but commented out with `#`. Find it — it will look like this:

```hcl
# resource "aws_dynamodb_table" "terraform_locks" {
#   name         = "terraform-locks"
#   ...
# }
```

### The fix

Uncomment the entire block. Use `vi` to remove the `#` characters:

```bash
vi main.tf
```

The resource should look like this once uncommented:

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

**Why `LockID`?** This is a hard requirement from Terraform's S3 backend. The S3 backend specifically looks for a DynamoDB item with the key `LockID`. Any other name — even `Lock_ID` or `lockid` — will cause locking to fail silently. The lock writes will appear to succeed, but Terraform won't actually check for existing locks.

**Why `PAY_PER_REQUEST`?** In a lab environment (and often in production for low-frequency Terraform runs), you pay per read/write operation rather than provisioning capacity upfront. For a table that's only written to when someone runs Terraform, this is more cost-effective.

---

## Step 3 — Add Server-Side Encryption to the S3 Bucket

### What problem are you solving?

The state file can contain sensitive data: resource IDs, IP addresses, ARNs, and sometimes database passwords or API keys if those are managed by Terraform. Without encryption, anyone with S3 read access can open the file and read this data in plain text.

### What to look for

Check whether an `aws_s3_bucket_server_side_encryption_configuration` resource exists in `main.tf`. It won't be there — that's the gap.

### The fix

Add this resource block to `main.tf`:

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

**Command breakdown — key fields:**

| Field | What it does |
|-------|-------------|
| `bucket` | References the existing S3 bucket by its Terraform resource ID |
| `rule` | Defines an encryption rule to apply to all objects |
| `apply_server_side_encryption_by_default` | Applies encryption to all objects unless explicitly overridden |
| `sse_algorithm = "aws:kms"` | Uses AWS Key Management Service for encryption. `AES256` is the simpler alternative using S3-managed keys |

---

## Step 4 — Add a Public Access Block to the S3 Bucket

### What problem are you solving?

Even if the bucket doesn't have a public bucket policy right now, someone could accidentally add one in future. The public access block is a hard override — it prevents any configuration from making the bucket publicly accessible, regardless of what policies exist.

### The fix

Add this resource block to `main.tf`:

```hcl
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

**Field breakdown:**

| Field | What it does |
|-------|-------------|
| `block_public_acls` | Blocks any PUT requests that include a public ACL |
| `block_public_policy` | Blocks any bucket policy that grants public access |
| `ignore_public_acls` | Ignores any existing public ACLs on objects |
| `restrict_public_buckets` | Restricts access to the bucket owner and AWS services only |

---

## Step 5 — Initialise Terraform

Before making any changes, initialise Terraform to download the AWS provider:

```bash
terraform init
```

**Command breakdown:**

| Part | What it does |
|------|-------------|
| `terraform` | Invokes the Terraform CLI |
| `init` | Initialises the working directory — downloads provider plugins, prepares backend |

At this point, the backend block is still commented out, so Terraform initialises with local state. That is intentional — you need the infrastructure to exist before you can configure the backend to use it.

---

## Step 6 — Check What Terraform Thinks It Knows

Before touching `main.tf`, run:

```bash
terraform show
```

**What you'll see:** Terraform reads the local `terraform.tfstate` stub file (placed there by the setup script) and displays it as if those resources are already managed. It will show the S3 bucket as an existing resource.

**Important:** This is not reading from AWS. It is reading from the local state file only. Terraform has no way of knowing whether those resources actually exist in AWS at this point — it just trusts what the state file says. This is exactly the fragility the lab is solving: a state file on one machine, trusted blindly, with no backup.

---

## Step 7 — The Chicken-and-Egg Problem (Read This Before Touching main.tf)

This is the most important concept in the lab, and you will hit it as a real error if you don't understand the sequence.

**The problem:** The backend block references a DynamoDB table for locking. The moment you add the backend block and run `terraform init`, Terraform immediately tries to acquire a lock in that DynamoDB table. But the DynamoDB table doesn't exist yet — it's still commented out in `main.tf` and hasn't been applied. You get this error:

```
Error: Error acquiring the state lock
ResourceNotFoundException: Requested resource not found
```

**Why this happens:** Terraform tries to lock state before doing anything else — even before creating resources. It can't lock a table that doesn't exist yet.

**The solution — a two-stage process:**

| Stage | What you do | Backend state |
|-------|-------------|---------------|
| Stage 1 | Keep backend block commented out. Make all other fixes. Run `terraform apply`. | Local |
| Stage 2 | Uncomment backend block. Run `terraform init -migrate-state`. | Migrates to S3 |

You must apply all the infrastructure (DynamoDB table, encryption, public access block) with the backend still local, then and only then switch the backend to S3.

**In real production:** Teams solve this by keeping the backend infrastructure in a completely separate "bootstrap" Terraform configuration that always uses local state. All other Terraform projects then reference that pre-existing backend. In this lab, we solve it with the two-stage approach.

---

## Step 8 — Make All Fixes (Backend Still Commented Out)

Make the following changes to `main.tf`. **Leave the backend block commented out for now.**

```bash
vi main.tf
```

Your finished `main.tf` should look like this:

```hcl
# Remote Backend Lab
provider "aws" {
  region = "eu-west-2"
}

# TASK: Add a terraform backend block for S3
# terraform {
#   backend "s3" {
#     bucket         = "terraform-state-340752829546"
#     key            = "production/terraform.tfstate"
#     region         = "eu-west-2"
#     dynamodb_table = "terraform-locks"
#     encrypt        = true
#   }
# }

resource "aws_s3_bucket" "terraform_state" {
  bucket = "terraform-state-340752829546"
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "production-vpc" }
}
```

---

## Step 9 — Apply the Infrastructure (Stage 1)

With the backend still local, apply all the fixes:

```bash
terraform apply
```

Type `yes` when prompted.

**What Terraform will create:**

| Resource | Why |
|----------|-----|
| `aws_dynamodb_table.terraform_locks` | The locking table — must exist before the backend can reference it |
| `aws_s3_bucket_server_side_encryption_configuration` | Encrypts all objects written to the state bucket |
| `aws_s3_bucket_public_access_block` | Hard blocks any public access to the state bucket |
| `aws_s3_bucket_versioning` | Enables versioning so state file overwrites are recoverable |
| `aws_vpc.main` | The "production infrastructure" the state is tracking |

**Note:** The S3 bucket itself already exists (created by the setup script) so Terraform will refresh it from state but not recreate it.

After apply completes you should see:

```
Apply complete! Resources: 5 added, 0 changed, 0 destroyed.
```

---

## Step 10 — Uncomment the Backend Block (Stage 2)

Now that the DynamoDB table exists in AWS, it is safe to add the backend block. Open `main.tf` and uncomment it:

```bash
vi main.tf
```

The backend block should look like this:

```hcl
terraform {
  backend "s3" {
    bucket         = "terraform-state-340752829546"
    key            = "production/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
```

**Backend argument breakdown:**

| Argument | What it does |
|----------|-------------|
| `bucket` | The S3 bucket where state will be stored — must already exist |
| `key` | The path inside the bucket for the state file — allows multiple environments in one bucket |
| `region` | The AWS region the bucket lives in |
| `dynamodb_table` | The locking table — must match the resource name exactly |
| `encrypt` | Instructs Terraform to encrypt the state file when writing to S3 |

---

## Step 11 — Migrate State to S3

Now run:

```bash
terraform init -migrate-state
```

**Command breakdown:**

| Part | What it does |
|------|-------------|
| `terraform` | Invokes the Terraform CLI |
| `init` | Initialises the working directory and configures the backend |
| `-migrate-state` | Detects the backend has changed from local to S3, and offers to copy the existing local state across |

**What you will see:**

```
Pre-existing state was found while migrating the previous "local" backend to the
newly configured "s3" backend. No existing state was found in the newly
configured "s3" backend. Do you want to copy this state to the new "s3" backend?
Enter "yes" to copy and "no" to start with an empty state.
```

Type `yes`. Terraform copies the local state to S3. From this point forward, all Terraform commands read and write state from S3.

**About the local state file after migration:**
Terraform leaves `terraform.tfstate` on disk after migration as a safety backup. This is intentional and correct behaviour — do not delete it immediately. In production, engineers leave it in place until they have confirmed the remote backend is working correctly across several runs. Once confident, it can be removed. It is no longer the active backend — that is now S3.

**About state locking — it is completely automatic:**
You never interact with DynamoDB directly. When you run any Terraform command, Terraform automatically writes a lock entry to the DynamoDB table before doing any work, and deletes it when done. If another engineer tries to run Terraform while you hold the lock, they see an error telling them who holds the lock and when they acquired it. The only time you interact with DynamoDB manually is if a crash leaves a stale lock — in that case you run `terraform force-unlock <lock-id>` to clear it.

---

## Step 12 — Validate

```bash
terraform validate
terraform plan
```

**`terraform validate`** checks syntax and internal consistency. Does not contact AWS.

**`terraform plan`** reads state from S3 (not local), compares against AWS, and confirms everything matches. You should see:

```
No changes. Your infrastructure matches the configuration.
```

This confirms the migration worked — Terraform is reading from S3, the state matches reality, and nothing needs creating or destroying.

---

## Lab vs Real Life

| Lab behaviour | Real-life equivalent |
|---------------|---------------------|
| Two-stage apply (local first, then migrate) | Production uses a separate "bootstrap" Terraform config that always uses local state to create the backend infrastructure. All other configs reference that pre-existing backend |
| Single bucket for all state | Teams typically use one bucket with multiple `key` paths: `dev/terraform.tfstate`, `staging/terraform.tfstate`, `production/terraform.tfstate` |
| `aws:kms` with default AWS-managed key | Production often uses a customer-managed KMS key (CMK) for auditability and key rotation control |
| S3 + DynamoDB backend | Many teams use Terraform Cloud or Terraform Enterprise instead — built-in state storage, locking, run history, and team collaboration |
| `terraform destroy` to clean up | In production you would never destroy the state bucket — it is permanent infrastructure |
| Local state file retained after migration | In production, the local file is left as a backup and only removed once the team is confident the remote backend is stable |

---

## Key Concepts to Remember

- **Remote state prevents state loss.** Local state files are fragile. S3 with versioning is durable, backed up, and accessible to the whole team.
- **DynamoDB locking is automatic.** You never write to DynamoDB yourself. Terraform acquires and releases locks automatically on every command.
- **The hash key must be exactly `LockID`.** Any other name — including different casing — causes locking to fail silently.
- **Backend infrastructure must exist before the backend block.** Always apply first with local state, then add the backend block and migrate.
- **`terraform init -migrate-state` is the migration command.** It detects the backend change and copies state across. Without it, Terraform starts with empty state and tries to recreate everything.
- **The local state file after migration is a backup, not a problem.** Terraform leaves it intentionally. It is no longer the active backend.
- **Don't `git pull` mid-session with unsaved `main.tf` changes.** If you need to pull during a lab, stash first: `git stash`, `git pull`, `git stash pop`.

---

## Common Mistakes

- **Adding the backend block before applying.** You will get `ResourceNotFoundException` from DynamoDB because the table doesn't exist yet. Always apply the infrastructure first.
- **Forgetting `-migrate-state`.** Without it, Terraform initialises with empty state and will try to create duplicate resources.
- **Wrong DynamoDB hash key.** Must be exactly `LockID` — capital L, capital I, capital D. Wrong casing fails silently.
- **Not enabling S3 versioning.** Without versioning, an accidental state overwrite is permanent.
- **Assuming the local state file after migration is an error.** It is a backup. Terraform leaves it intentionally.
- **Running `git pull` mid-session.** This will overwrite your `main.tf` changes back to the broken starting state.

---

## Teardown — After the Lab

The teardown script handles cleanup in the correct order:

```bash
chmod +x teardown.sh
./teardown.sh
```

**What the teardown script does, in order:**

| Step | Action | Why this order matters |
|------|--------|----------------------|
| 1 | Pulls remote state down to a local backup | State must be local before the remote backend can be removed |
| 2 | Writes a temporary `override.tf` forcing local backend | Terraform can't destroy if the backend (S3/DynamoDB) is already gone |
| 3 | Runs `terraform init -migrate-state` back to local | Switches Terraform's active backend from S3 to local |
| 4 | Runs `terraform destroy` | Removes DynamoDB table, encryption config, public access block, versioning, VPC |
| 5 | Empties all object versions from the S3 bucket | S3 buckets with versioning enabled cannot be deleted until all versions and delete markers are removed — `terraform destroy` alone will fail on this |
| 6 | Deletes the S3 bucket | Bucket is now empty and can be deleted |
| 7 | Cleans up local Terraform files | Leaves the directory clean for the next run |

**Important note on the S3 bucket deletion:**
`terraform destroy` cannot delete a versioned S3 bucket that contains objects. The state file (and its versions) live in the bucket, so Terraform will error at this step if run manually. The teardown script handles this by emptying all versions before attempting deletion. If you ever tear down manually rather than using the script, you must empty the bucket first:

```bash
# Empty all versions manually
aws s3api delete-objects \
  --bucket terraform-state-340752829546 \
  --delete "$(aws s3api list-object-versions \
    --bucket terraform-state-340752829546 \
    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
    --output json)"

# Then delete the bucket
aws s3api delete-bucket \
  --bucket terraform-state-340752829546 \
  --region eu-west-2
```

**After teardown:** The repo already holds `main.tf` in its broken starting state — you do not need to revert anything. The lab is ready for the next run.
