#!/bin/bash
# =============================================================================
# Lab 068 — Scenario Setup Script
# =============================================================================
# Recreates the state an engineer would inherit when SUPPORT-4471 lands.
# Assumes `terraform apply` has already been run successfully.
#
# What this does (pure scaffolding, NOT part of the diagnostic flow):
#   1. Reads distribution ID, domain name, and bucket name from Terraform state
#   2. Waits for the CloudFront distribution to reach Deployed status
#   3. Uploads pricing.html v1 ("old" version)
#   4. Primes the CloudFront edge cache by fetching v1 through the distribution
#   5. Overwrites pricing.html in S3 with v2 ("new" version marketing uploaded)
#
# End state: S3 holds v2, CloudFront edge cache holds v1, customers complain.
# =============================================================================

set -eo pipefail

# -----------------------------------------------------------------------------
# Sanity checks — fail loud and early
# -----------------------------------------------------------------------------
if ! command -v terraform &>/dev/null; then
    echo "ERROR: terraform not found in PATH" >&2
    exit 1
fi

if ! command -v aws &>/dev/null; then
    echo "ERROR: aws CLI not found in PATH" >&2
    exit 1
fi

if [[ ! -f main.tf ]]; then
    echo "ERROR: main.tf not found — run this from the lab directory" >&2
    exit 1
fi

if [[ ! -f terraform.tfstate ]]; then
    echo "ERROR: no terraform.tfstate found — run 'terraform apply' first" >&2
    exit 1
fi

# -----------------------------------------------------------------------------
# Extract values from Terraform outputs — guard against silent substitution
# -----------------------------------------------------------------------------
DIST_ID=$(terraform output -raw distribution_id 2>/dev/null || true)
DIST_DOMAIN=$(terraform output -raw distribution_domain_name 2>/dev/null || true)
BUCKET=$(terraform output -raw bucket_name 2>/dev/null || true)

if [[ -z "$DIST_ID" || -z "$DIST_DOMAIN" || -z "$BUCKET" ]]; then
    echo "ERROR: Could not read Terraform outputs. Expected:" >&2
    echo "  - distribution_id" >&2
    echo "  - distribution_domain_name" >&2
    echo "  - bucket_name" >&2
    echo "Has 'terraform apply' been run successfully?" >&2
    exit 1
fi

# -----------------------------------------------------------------------------
# Wait for the distribution to reach Deployed status
# -----------------------------------------------------------------------------
echo "Waiting for CloudFront distribution to deploy..."
ATTEMPTS=0
MAX_ATTEMPTS=30   # 30 x 20s = 10 minutes max

while true; do
    STATUS=$(aws cloudfront get-distribution \
        --id "$DIST_ID" \
        --query 'Distribution.Status' \
        --output text 2>/dev/null || echo "Unknown")

    if [[ "$STATUS" == "Deployed" ]]; then
        echo "  Distribution deployed."
        break
    fi

    ATTEMPTS=$((ATTEMPTS+1))
    if [[ "$ATTEMPTS" -ge "$MAX_ATTEMPTS" ]]; then
        echo "ERROR: Distribution did not reach Deployed state within 10 minutes" >&2
        echo "Current status: $STATUS" >&2
        exit 1
    fi

    printf "  Status: %s (attempt %d/%d) — waiting 20s...\n" "$STATUS" "$ATTEMPTS" "$MAX_ATTEMPTS"
    sleep 20
done

# -----------------------------------------------------------------------------
# Upload v1 — the "old" version that will become stale cached content
# -----------------------------------------------------------------------------
echo "Uploading pricing.html v1 to S3..."
echo "<h1>Pricing v1 — OLD VERSION</h1>" | \
    aws s3 cp - "s3://${BUCKET}/pricing.html" \
    --content-type "text/html" \
    --quiet

# -----------------------------------------------------------------------------
# Prime the CloudFront edge cache with v1
# -----------------------------------------------------------------------------
echo "Priming CloudFront edge cache with v1..."
curl -s -o /dev/null "https://${DIST_DOMAIN}/pricing.html"

# -----------------------------------------------------------------------------
# Overwrite with v2 — simulates marketing's update
# -----------------------------------------------------------------------------
echo "Uploading pricing.html v2 (simulating marketing's update)..."
echo "<h1>Pricing v2 — NEW VERSION</h1>" | \
    aws s3 cp - "s3://${BUCKET}/pricing.html" \
    --content-type "text/html" \
    --quiet

# -----------------------------------------------------------------------------
# Done — print the incident briefing
# -----------------------------------------------------------------------------
cat <<EOF

=============================================================================
SUPPORT-4471                                            Priority: HIGH
Raised: marketing@company.com                           Status: Open
=============================================================================

Subject: Pricing page showing outdated figures

Hi,

Our pricing page is still showing the old figures. We updated it in the
S3 bucket this morning but customers are still seeing yesterday's version.
Multiple complaints on Twitter already.

Please investigate urgently.

Thanks,
Marketing

=============================================================================

You are the engineer on call. You have access to the AWS account and
the infrastructure Terraform repo. Good luck.

=============================================================================

EOF
