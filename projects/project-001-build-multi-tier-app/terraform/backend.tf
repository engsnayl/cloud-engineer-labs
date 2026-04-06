# =============================================================================
# FILE: terraform/backend.tf
# PURPOSE: Configures remote state storage in S3 with DynamoDB locking.
#
# WHAT IS TERRAFORM STATE?
#   Terraform keeps track of every resource it creates in a "state file"
#   (terraform.tfstate). This file maps your .tf code to real AWS resources.
#   Without it, Terraform wouldn't know what already exists and would try
#   to create everything from scratch every time.
#
# WHY REMOTE STATE?
#   By default, the state file is stored locally on your computer. This is
#   fine for learning solo, but has problems:
#   1. If you lose the file, Terraform loses track of ALL your resources.
#      You'd have to manually import or delete everything.
#   2. If two people run Terraform at the same time, they'll overwrite
#      each other's state — potentially corrupting it.
#   3. The state file can contain sensitive data (database passwords, etc.)
#      and shouldn't live on a laptop unencrypted.
#
# HOW S3 + DYNAMODB BACKEND WORKS:
#   - S3 bucket: stores the state file (encrypted, versioned, durable)
#   - DynamoDB table: provides a "lock" so only one person can modify the
#     state at a time (prevents corruption from concurrent runs)
#
# SETUP INSTRUCTIONS:
#   Before uncommenting the backend block below, you need to create the S3
#   bucket and DynamoDB table. You can do this manually in the AWS Console
#   or with the AWS CLI:
#
#   Step 1: Create the S3 bucket (replace ACCOUNT-ID with your 12-digit AWS account ID)
#     aws s3api create-bucket \
#       --bucket multi-tier-app-tfstate-ACCOUNT-ID \
#       --region eu-west-2 \
#       --create-bucket-configuration LocationConstraint=eu-west-2
#
#   Step 2: Enable versioning on the bucket (so you can recover old state files)
#     aws s3api put-bucket-versioning \
#       --bucket multi-tier-app-tfstate-ACCOUNT-ID \
#       --versioning-configuration Status=Enabled
#
#   Step 3: Enable encryption (protects sensitive data in the state file)
#     aws s3api put-bucket-encryption \
#       --bucket multi-tier-app-tfstate-ACCOUNT-ID \
#       --server-side-encryption-configuration \
#         '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
#
#   Step 4: Create the DynamoDB table for state locking
#     aws dynamodb create-table \
#       --table-name multi-tier-app-tfstate-lock \
#       --attribute-definitions AttributeName=LockID,AttributeType=S \
#       --key-schema AttributeName=LockID,KeyType=HASH \
#       --billing-mode PAY_PER_REQUEST \
#       --region eu-west-2
#
#   Step 5: Uncomment the terraform block below
#
#   Step 6: Run "terraform init" to migrate your local state to S3
#     Terraform will ask: "Do you want to copy existing state to the new backend?"
#     Type "yes".
#
# COST NOTE:
#   - S3: Pennies per month for a state file (they're tiny, usually under 1MB)
#   - DynamoDB (PAY_PER_REQUEST): Essentially free for Terraform locking
#     (you'll make maybe a few requests per day)
# =============================================================================

# UNCOMMENT THE BLOCK BELOW after creating the S3 bucket and DynamoDB table.
# Replace "ACCOUNT-ID" with your actual AWS account ID (found in the AWS Console
# under your account name in the top-right corner, e.g., 123456789012).

# terraform {
#   backend "s3" {
#     bucket         = "multi-tier-app-tfstate-ACCOUNT-ID"  # S3 bucket name (must be globally unique)
#     key            = "terraform.tfstate"                   # Path inside the bucket for the state file
#     region         = "eu-west-2"                           # Region where the bucket lives
#     encrypt        = true                                  # Encrypt the state file at rest in S3
#     dynamodb_table = "multi-tier-app-tfstate-lock"         # DynamoDB table for state locking
#
#     # WHAT EACH SETTING DOES:
#     # - bucket: the S3 bucket that holds your state file
#     # - key: the "path" inside the bucket (like a filename)
#     # - region: which region the S3 bucket is in
#     # - encrypt: ensures the state file is encrypted at rest (AES-256)
#     # - dynamodb_table: prevents two people from modifying state at the same time
#   }
# }
