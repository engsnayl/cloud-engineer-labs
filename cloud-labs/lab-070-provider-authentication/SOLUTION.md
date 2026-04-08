# Lab 070 — Provider Authentication
## Solution Walkthrough

---

## Plain-English TLDR

You've been handed a Terraform configuration that won't initialise. The configuration is trying to deploy S3 buckets into two different AWS regions — one in London, one in the US — but there are three mistakes in the provider setup that stop Terraform from even getting started.

**In plain terms:**

1. Someone typed a fake AWS region (`eu-west-99`). AWS doesn't have that region, so Terraform can't connect to anything.
2. There are two AWS provider blocks but neither has a label (alias). Terraform sees this as a duplicate definition and refuses to continue — it doesn't know which one to use for which resource.
3. One of the S3 buckets is asking to use a provider with the label `backup_region` — but that label doesn't exist on any provider block. Terraform can't find what the resource is pointing at.

Fix all three and `terraform init` + `terraform plan` will succeed.

---

## Background: What Is a Terraform Provider?

A **provider** is the plugin that lets Terraform talk to a cloud platform. For AWS, the provider block tells Terraform:

- Which **region** to connect to
- Which **credentials** to use (from your environment, not hardcoded)

When you need resources in more than one region, you define **multiple provider blocks** — but Terraform needs a way to tell them apart. That's what **aliases** are for. An alias is just a label you assign to a provider block. Resources can then reference that label using `provider = aws.<alias_name>`.

If a resource doesn't reference any provider, Terraform uses the **default provider** (the one with no alias). If a resource specifies `provider = aws.something`, Terraform looks for a provider block with `alias = "something"`.

---

## Real-Time Investigative Learning Pathway

### Step 1 — You receive the ticket. What do you know?

The ticket says: *Terraform is failing. It won't init or plan. Fix it.*

That's it. You don't know what's broken. The first thing you do is orient yourself — understand the structure of what you're working with before running anything.

```bash
ls -la
```

| Part | What it does |
|------|--------------|
| `ls` | Lists directory contents |
| `-l` | Long format — shows file permissions, size, dates |
| `-a` | Includes hidden files (dotfiles like `.terraform`) |

You're looking for: `main.tf`, `variables.tf`, `outputs.tf`, and any existing `.terraform/` directory.

Now read the Terraform config before touching anything:

```bash
cat main.tf
```

Take your time here. Read every block. You're looking for the structure — how many provider blocks are there? What regions are listed? What resources are defined, and do they reference any providers explicitly?

---

### Step 2 — Run `terraform init` and read the error

You don't know what's wrong yet. Run init and see what Terraform tells you:

```bash
terraform init
```

| Part | What it does |
|------|--------------|
| `terraform init` | Initialises the working directory — downloads provider plugins, sets up backend |

**What would you expect if this worked?** A message like: `Terraform has been successfully initialized!`

**What are you likely to see instead?** An error. Read it carefully — Terraform error messages are usually specific about what failed.

**What kind of errors would stop init?**
- An invalid region (Terraform validates this when setting up the provider)
- A configuration syntax error
- A duplicate provider block

> **"How would I know this?"** — `terraform init` is the first command you always run in a new directory. It's your entry point. If it fails, nothing else can run. The error message from init is your primary diagnostic tool right now.

---

### Step 3 — Identify Bug 1: Invalid region

Look at the first provider block in `main.tf`. You'll see:

```hcl
provider "aws" {
  region = "eu-west-99"
}
```

**Stop. Does this look right?**

AWS regions follow a specific naming pattern: `<geography>-<direction>-<number>`. For example:
- `eu-west-1` → Ireland
- `eu-west-2` → London
- `us-east-1` → Northern Virginia
- `ap-southeast-1` → Singapore

`eu-west-99` doesn't match anything real. There are only a handful of EU West regions (1, 2, and 3). **99 doesn't exist.**

> **"How would I know this?"** — AWS has a finite, documented list of regions. If you're unsure, you can verify with the AWS CLI:

```bash
aws ec2 describe-regions --query "Regions[].RegionName" --output table
```

| Part | What it does |
|------|--------------|
| `aws ec2 describe-regions` | Calls the EC2 API to list all enabled AWS regions |
| `--query "Regions[].RegionName"` | Filters the JSON response to only show region names |
| `--output table` | Formats the output as a readable table instead of raw JSON |

**Fix:** Change `eu-west-99` to a real region. In this lab context we'll use `eu-west-2` (London):

```hcl
provider "aws" {
  region = "eu-west-2"
}
```

---

### Step 4 — Identify Bug 2: Two providers, no aliases

Now look at the rest of `main.tf`. You'll see a second provider block:

```hcl
provider "aws" {
  region = "us-east-1"
}
```

**Two `provider "aws"` blocks. No alias on either one.**

Ask yourself: how does Terraform know which provider to use for which resource when there are two?

It can't. Terraform requires that if you have more than one block of the same provider type, all but one must have an **alias**. The un-aliased block becomes the default. The aliased blocks are used only when a resource explicitly references them.

Without aliases, Terraform will throw a **duplicate provider configuration** error. It's not guessing which one you meant — it refuses to continue.

> **"How would I know this?"** — The Terraform error message will tell you: `"Duplicate provider configuration for "aws""`. But even before that, the moment you see two provider blocks of the same type without aliases, that's the bug. It's a pattern you'll recognise quickly.

**Fix:** Add an alias to the second provider block:

```hcl
provider "aws" {
  alias  = "backup_region"
  region = "us-east-1"
}
```

| Part | What it does |
|------|--------------|
| `alias = "backup_region"` | Gives this provider a name so Terraform can tell it apart from the default |
| `region = "us-east-1"` | Tells Terraform which AWS region to use when this provider is invoked |

---

### Step 5 — Identify Bug 3: Resource references an alias that doesn't exist

Now look at the S3 bucket resource in `main.tf`:

```hcl
resource "aws_s3_bucket" "backup" {
  provider = aws.backup_region
  bucket   = "backup-data-bucket"
}
```

The resource is saying: *"Use the AWS provider with alias `backup_region`."*

**Ask yourself: does that alias currently exist?**

Before the fix in Step 4, the answer is no — neither provider block had any alias. The resource is pointing at something that doesn't exist.

After adding `alias = "backup_region"` in Step 4, this reference is now valid. The alias name in the provider block must match exactly what the resource references.

> **"How would I know this?"** — Terraform would tell you: `"There is no explicit mapping from the provider "aws.backup_region"`. But the investigative move here is to check whether every `provider = aws.<something>` reference in your resource blocks has a matching `alias = "<something>"` in a provider block. This is a quick grep:

```bash
grep -n "provider = aws\." main.tf
```

| Part | What it does |
|------|--------------|
| `grep` | Searches for a pattern in a file |
| `-n` | Shows the line number where each match is found |
| `"provider = aws\."` | The pattern to search for — the `\.` escapes the dot so it matches literally |
| `main.tf` | The file to search in |

Then run:

```bash
grep -n "alias" main.tf
```

Compare the two outputs. Every alias referenced by a resource must appear in a provider block. If they don't match, you've found the bug.

---

### Step 6 — Apply all fixes and validate

The complete fixed `main.tf` looks like this:

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

Now validate:

```bash
terraform init
```

Expected output: `Terraform has been successfully initialized!`

```bash
terraform validate
```

| Part | What it does |
|------|--------------|
| `terraform validate` | Checks the configuration for syntax errors and internal consistency — does not connect to AWS |

Expected output: `Success! The configuration is valid.`

```bash
terraform plan
```

| Part | What it does |
|------|--------------|
| `terraform plan` | Connects to AWS and shows what changes Terraform would make — does not apply anything |

Expected output: A plan showing two S3 buckets to be created — one in `eu-west-2`, one in `us-east-1`.

> **Note:** `terraform plan` requires valid AWS credentials. These are resolved from your environment (environment variables, shared credentials file, or IAM role) — not from the provider block itself.

---

## Lab vs Real Life

| Lab | Real Life |
|-----|-----------|
| Credentials come from your environment automatically | Production Terraform uses IAM roles (`assume_role` in provider block) for explicit permission boundaries and audit trails |
| Two regions (London + US East) | Real multi-region setups often span 3+ regions, sometimes across multiple AWS accounts |
| Provider bugs are obvious once you look | In large codebases, provider alias mismatches can be hard to spot — `grep` and `terraform validate` are your friends |
| No version pinning | Production always pins provider versions: `required_providers { aws = { version = "~> 5.0" } }` to prevent breaking changes |
| Single backend | Real state is stored in S3 with DynamoDB locking — backend auth is separate from provider auth |

---

## Cleanup / Reset

This lab uses `terraform plan` only — no resources are actually created. If you ran `terraform apply` accidentally:

```bash
terraform destroy
```

To reset the lab to its broken starting state, discard your changes to `main.tf` using Git:

```bash
git checkout -- main.tf
```

| Part | What it does |
|------|--------------|
| `git checkout` | Restores files from Git's last committed state |
| `--` | Tells Git that what follows is a file path, not a branch name |
| `main.tf` | The file to restore — overwrites your local changes with the committed (broken) version |

Then confirm the reset worked:

```bash
terraform validate
```

You should see validation errors again — that means the lab is back in its broken state and ready to run from Step 1.

---

## Key Concepts

- **AWS region names are fixed strings** — `eu-west-2`, not `eu-west-99`. Use `aws ec2 describe-regions` to check.
- **Two providers of the same type need aliases** — Terraform doesn't allow duplicates without them.
- **`provider = aws.<alias>`** — the alias name in the resource must match the alias name on the provider block exactly. Case-sensitive.
- **`terraform init` validates provider config** — invalid regions and duplicate providers are caught here, not at plan time.
- **Credentials are not in the provider block** — they come from the environment via the AWS credential chain.
