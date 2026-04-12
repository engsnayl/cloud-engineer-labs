#!/bin/bash
# =============================================================================
# Validation: Lab 068 — CloudFront Stale Content
# =============================================================================
# Verifies BOTH bugs are fixed:
#   Bug 1: Origin uses S3 website endpoint (not REST API endpoint)
#   Bug 2: Cache TTLs are set to reasonable values
# =============================================================================

echo "Running Lab 068 validation..."
echo ""

PASS=0
FAIL=0

check() {
    local description="$1"
    local result="$2"
    if [[ "$result" -eq 0 ]]; then
        echo "  ✅  $description"
        PASS=$((PASS+1))
    else
        echo "  ❌  $description"
        FAIL=$((FAIL+1))
    fi
}

# -----------------------------------------------------------------------------
# Check 1: Terraform syntax is valid
# -----------------------------------------------------------------------------
terraform validate &>/dev/null
check "Terraform configuration is syntactically valid" $?

# -----------------------------------------------------------------------------
# Check 2: Terraform plan completes without errors
# -----------------------------------------------------------------------------
terraform plan -detailed-exitcode &>/dev/null
plan_exit=$?
# 0 = no changes, 2 = changes pending, 1 = error
if [[ "$plan_exit" -eq 1 ]]; then
    check "Terraform plan completes without errors" 1
else
    check "Terraform plan completes without errors" 0
fi

# -----------------------------------------------------------------------------
# Generate plan JSON once for the resource-level checks below
# -----------------------------------------------------------------------------
PLAN_JSON=$(mktemp)
trap 'rm -f "$PLAN_JSON" "${PLAN_JSON}.bin"' EXIT

if ! terraform plan -out="${PLAN_JSON}.bin" &>/dev/null; then
    echo "  ❌  Could not generate plan for inspection — aborting deeper checks"
    echo ""
    echo "Results: $PASS passed, $((FAIL+1)) failed"
    exit 1
fi
terraform show -json "${PLAN_JSON}.bin" > "$PLAN_JSON" 2>/dev/null

# Extract the CloudFront distribution resource from the plan
DIST=$(jq -r '
    .planned_values.root_module.resources[]
    | select(.type == "aws_cloudfront_distribution")
' "$PLAN_JSON" 2>/dev/null)

if [[ -z "$DIST" ]]; then
    check "CloudFront distribution resource found in plan" 1
    echo ""
    echo "Results: $PASS passed, $FAIL failed"
    exit 1
fi
check "CloudFront distribution resource found in plan" 0

# -----------------------------------------------------------------------------
# Check 3 (Bug 1): Origin uses the S3 website endpoint, not REST API endpoint
# -----------------------------------------------------------------------------
# The website endpoint resolves to a domain containing "s3-website" — the
# REST endpoint looks like "<bucket>.s3.<region>.amazonaws.com". We check
# the Terraform config source since the domain_name is a resource reference.
if grep -Eq 'domain_name[[:space:]]*=[[:space:]]*aws_s3_bucket_website_configuration\.' main.tf; then
    check "Origin uses S3 website endpoint (Bug 1 fixed)" 0
else
    check "Origin uses S3 website endpoint (Bug 1 fixed) — still pointing at bucket_regional_domain_name?" 1
fi

# Also verify custom_origin_config is present (required for website endpoint)
if grep -q 'custom_origin_config' main.tf; then
    check "custom_origin_config block present (required for website endpoint)" 0
else
    check "custom_origin_config block present (required for website endpoint)" 1
fi

# -----------------------------------------------------------------------------
# Check 4 (Bug 2): Cache TTLs are sane
# -----------------------------------------------------------------------------
DEFAULT_TTL=$(echo "$DIST" | jq -r '.values.default_cache_behavior[0].default_ttl // empty')
MAX_TTL=$(echo "$DIST" | jq -r '.values.default_cache_behavior[0].max_ttl // empty')
MIN_TTL=$(echo "$DIST" | jq -r '.values.default_cache_behavior[0].min_ttl // empty')

# default_ttl should be <= 1 day (86400). Original broken value was 604800 (7 days).
if [[ -n "$DEFAULT_TTL" && "$DEFAULT_TTL" -le 86400 ]]; then
    check "default_ttl is reasonable (<= 1 day): ${DEFAULT_TTL}s" 0
else
    check "default_ttl is too long (found: ${DEFAULT_TTL}s, expected <= 86400)" 1
fi

# max_ttl should be <= 1 week (604800). Original broken value was 31536000 (1 year).
if [[ -n "$MAX_TTL" && "$MAX_TTL" -le 604800 ]]; then
    check "max_ttl is reasonable (<= 1 week): ${MAX_TTL}s" 0
else
    check "max_ttl is too long (found: ${MAX_TTL}s, expected <= 604800)" 1
fi

# min_ttl should be low enough that the origin can control caching (<= 60s)
if [[ -n "$MIN_TTL" && "$MIN_TTL" -le 60 ]]; then
    check "min_ttl allows origin to control caching (<= 60s): ${MIN_TTL}s" 0
else
    check "min_ttl too high — origin cannot control caching (found: ${MIN_TTL}s)" 1
fi

# -----------------------------------------------------------------------------
# Check 5 (Bug 3): Public access block exists and allows public access
# -----------------------------------------------------------------------------
PAB=$(jq -r '
    .planned_values.root_module.resources[]
    | select(.type == "aws_s3_bucket_public_access_block")
' "$PLAN_JSON" 2>/dev/null)

if [[ -z "$PAB" ]]; then
    check "aws_s3_bucket_public_access_block resource present (Bug 3 fix)" 1
else
    check "aws_s3_bucket_public_access_block resource present (Bug 3 fix)" 0

    BLOCK_POLICY=$(echo "$PAB" | jq -r '.values.block_public_policy')
    RESTRICT=$(echo "$PAB" | jq -r '.values.restrict_public_buckets')

    if [[ "$BLOCK_POLICY" == "false" ]]; then
        check "block_public_policy disabled (allows bucket policy to take effect)" 0
    else
        check "block_public_policy is still true — bucket policy will be rejected" 1
    fi

    if [[ "$RESTRICT" == "false" ]]; then
        check "restrict_public_buckets disabled (allows public access)" 0
    else
        check "restrict_public_buckets is still true — public access will be denied" 1
    fi
fi

# -----------------------------------------------------------------------------
# Check 6 (Bug 3): Bucket policy grants public read
# -----------------------------------------------------------------------------
POLICY=$(jq -r '
    .planned_values.root_module.resources[]
    | select(.type == "aws_s3_bucket_policy")
    | .values.policy
' "$PLAN_JSON" 2>/dev/null)

if [[ -z "$POLICY" ]]; then
    check "aws_s3_bucket_policy resource present (Bug 3 fix)" 1
else
    check "aws_s3_bucket_policy resource present (Bug 3 fix)" 0

    if echo "$POLICY" | grep -q '"s3:GetObject"' && echo "$POLICY" | grep -q '"\*"'; then
        check "Bucket policy grants s3:GetObject to public principal" 0
    else
        check "Bucket policy does not grant public s3:GetObject" 1
    fi
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
exit $?
