# Terraform State Backend Bootstrap

This workspace creates the S3 bucket and DynamoDB lock table used by the main Terraform workspace for remote state storage.

## Why this exists

The main workspace (`../`) is configured with an S3 backend pointing at `multi-tier-app-tfstate-${account_id}` and a DynamoDB lock table `multi-tier-app-tf-locks`. Terraform cannot create the resources that store its own state in the same workspace — chicken-and-egg. This sub-workspace solves that by:

1. Using **local state** (no `backend` block — state lives in `terraform.tfstate` in this directory).
2. Creating the bucket and table.
3. After which the main workspace can `terraform init` against the bucket.

## What it creates

| Resource | Name | Purpose |
|---|---|---|
| S3 bucket | `multi-tier-app-tfstate-<account-id>` | Remote state storage |
| DynamoDB table | `multi-tier-app-tf-locks` | State locking |

Bucket has versioning, SSE-S3 encryption, and full public access block. DynamoDB has point-in-time recovery.

## Usage

From this directory:

```bash
terraform init
terraform plan
terraform apply
```

After apply, the main workspace can be initialised:

```bash
cd ..
terraform init
```

## Tearing down

If you want to fully destroy the project (including state backend):

1. Run `terraform destroy` in the main workspace first.
2. Empty the state bucket: `aws s3 rm s3://multi-tier-app-tfstate-<account-id> --recursive` (or via console).
3. Run `terraform destroy` in this bootstrap workspace.

The `force_destroy` flag on the bucket is `false` by design — destroy will refuse if the bucket is non-empty. Empty it deliberately.

## State for this workspace

This workspace's state is local (`terraform.tfstate` in this directory). It is **gitignored**. If lost, you can recreate the bucket and table by re-running `terraform apply` — they're idempotent, and Terraform will simply import existing resources into a fresh state.

## Production differences

In a real production setup:

- The bucket would use a **customer-managed KMS key** rather than SSE-S3, for key-level audit and rotation.
- **MFA delete** would be enabled to require MFA for destructive bucket operations.
- The bootstrap state itself would be stored remotely (e.g., a separate "platform" account's pre-existing backend).
- Bucket and table would have `prevent_destroy = true` lifecycle rules.

These are deliberately omitted here for learning-project ergonomics; called out in the Module 1 SOLUTION doc.
