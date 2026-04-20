#!/bin/bash
# Lab 083 — WAF Rules validation
# Tests live AWS WAF configuration, not Terraform syntax

REGION="eu-west-2"
ACL_NAME="app-waf-acl"
OFFICE_IP_SET_NAME="office-ip-set"

PASS=0
FAIL=0

check() {
  local description="$1"
  local result="$2"
  if [[ "$result" == "0" ]]; then
    echo -e "  ✅  $description"
    ((PASS++))
  else
    echo -e "  ❌  $description"
    ((FAIL++))
  fi
}

echo "Running WAF validation against live AWS resources in $REGION..."
echo ""

# 1. Terraform config is syntactically valid
terraform validate &>/dev/null
check "Terraform configuration is valid" "$?"

# 2. Web ACL exists in AWS
ACL_ID=$(aws wafv2 list-web-acls --scope REGIONAL --region "$REGION" \
  --query "WebACLs[?Name=='$ACL_NAME'].Id" --output text 2>/dev/null)
[[ -n "$ACL_ID" && "$ACL_ID" != "None" ]]
check "Web ACL '$ACL_NAME' is deployed in AWS" "$?"

if [[ -z "$ACL_ID" || "$ACL_ID" == "None" ]]; then
  echo ""
  echo "Results: $PASS passed, $FAIL failed"
  echo "Cannot continue validation — Web ACL not found. Run 'terraform apply' first."
  exit 1
fi

# Fetch the full ACL once for subsequent checks
ACL_JSON=$(aws wafv2 get-web-acl --name "$ACL_NAME" --scope REGIONAL \
  --id "$ACL_ID" --region "$REGION" 2>/dev/null)

# 3. Rate limit threshold is sensible (>= 1000 per 5 minutes)
RATE_LIMIT=$(echo "$ACL_JSON" | \
  jq -r '.WebACL.Rules[] | select(.Name=="rate-limit") | .Statement.RateBasedStatement.Limit')
[[ "$RATE_LIMIT" =~ ^[0-9]+$ && "$RATE_LIMIT" -ge 1000 ]]
check "Rate-limit threshold is >= 1000 (current: ${RATE_LIMIT:-unset})" "$?"

# 4. Rate-limit rule is NOT priority 1 (allow/trusted rules should run first)
RATE_PRIORITY=$(echo "$ACL_JSON" | \
  jq -r '.WebACL.Rules[] | select(.Name=="rate-limit") | .Priority')
[[ "$RATE_PRIORITY" -gt 1 ]]
check "Rate-limit rule priority is not 1 (current: ${RATE_PRIORITY:-unset})" "$?"

# 5. A rule with 'Allow' action exists — indicates trusted IPs are whitelisted
ALLOW_RULE_COUNT=$(echo "$ACL_JSON" | \
  jq '[.WebACL.Rules[] | select(.Action.Allow != null)] | length')
[[ "$ALLOW_RULE_COUNT" -ge 1 ]]
check "At least one Allow rule exists in the Web ACL" "$?"

# 6. Office/private CIDRs are NOT in any block-action IP set
BLOCK_IP_SET_ARNS=$(echo "$ACL_JSON" | jq -r '
  .WebACL.Rules[]
  | select(.Action.Block != null)
  | .Statement.IPSetReferenceStatement.ARN // empty')

OFFICE_IN_BLOCK_LIST=0
for ARN in $BLOCK_IP_SET_ARNS; do
  IPSET_ID=$(echo "$ARN" | awk -F'/' '{print $NF}')
  IPSET_NAME=$(echo "$ARN" | awk -F'/' '{print $(NF-1)}')
  ADDRESSES=$(aws wafv2 get-ip-set --name "$IPSET_NAME" --scope REGIONAL \
    --id "$IPSET_ID" --region "$REGION" \
    --query 'IPSet.Addresses' --output text 2>/dev/null)
  if echo "$ADDRESSES" | grep -qE '(10\.0\.0\.0/8|192\.168\.1\.0/24)'; then
    OFFICE_IN_BLOCK_LIST=1
  fi
done
[[ "$OFFICE_IN_BLOCK_LIST" -eq 0 ]]
check "Office CIDRs (10.0.0.0/8, 192.168.1.0/24) are not in any block-action IP set" "$?"

# 7. Malicious IPs are still blocked somewhere
MALICIOUS_STILL_BLOCKED=0
for ARN in $BLOCK_IP_SET_ARNS; do
  IPSET_ID=$(echo "$ARN" | awk -F'/' '{print $NF}')
  IPSET_NAME=$(echo "$ARN" | awk -F'/' '{print $(NF-1)}')
  ADDRESSES=$(aws wafv2 get-ip-set --name "$IPSET_NAME" --scope REGIONAL \
    --id "$IPSET_ID" --region "$REGION" \
    --query 'IPSet.Addresses' --output text 2>/dev/null)
  if echo "$ADDRESSES" | grep -q "203.0.113.50/32"; then
    MALICIOUS_STILL_BLOCKED=1
  fi
done
[[ "$MALICIOUS_STILL_BLOCKED" -eq 1 ]]
check "Known malicious IP (203.0.113.50/32) is still in a block-action IP set" "$?"

# 8. Geo-block rule does not block GB, IE, or US directly
# (It's fine if GB/IE/US appear inside a not_statement — that means "allow only these")
GEO_BLOCK_DIRECT=$(echo "$ACL_JSON" | jq -r '
  .WebACL.Rules[]
  | select(.Action.Block != null)
  | select(.Statement.GeoMatchStatement != null)
  | .Statement.GeoMatchStatement.CountryCodes[]?' 2>/dev/null)

GEO_BLOCKS_CUSTOMERS=0
for CODE in GB IE US; do
  if echo "$GEO_BLOCK_DIRECT" | grep -qw "$CODE"; then
    GEO_BLOCKS_CUSTOMERS=1
  fi
done
[[ "$GEO_BLOCKS_CUSTOMERS" -eq 0 ]]
check "Geo rule does not directly block customer countries (GB, IE, US)" "$?"

# 9. CloudWatch metrics are enabled on the Web ACL (observability check)
METRICS_ENABLED=$(echo "$ACL_JSON" | \
  jq -r '.WebACL.VisibilityConfig.CloudWatchMetricsEnabled')
[[ "$METRICS_ENABLED" == "true" ]]
check "CloudWatch metrics are enabled on the Web ACL" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
