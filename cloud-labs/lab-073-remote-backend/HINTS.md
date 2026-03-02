# Hints — Cloud Lab 014: Remote Backend

## Hint 1 — Three things needed
1. S3 bucket with versioning for state storage. 2. DynamoDB table for state locking. 3. Backend configuration in terraform block.

## Hint 2 — Uncomment the DynamoDB table
The DynamoDB table resource is commented out. Uncomment it. The hash_key must be "LockID" — this is a Terraform convention.

## Hint 3 — Backend block
Uncomment and configure the backend "s3" block. Note: you'll need to run `terraform init -migrate-state` to move from local to remote.
