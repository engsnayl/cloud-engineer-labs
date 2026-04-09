#!/bin/bash
# =============================================================================
# validate.sh — Lab 092: Live Right-Sizing with AWS Compute Optimizer
# =============================================================================

set -euo pipefail

REGION="eu-west-2"
PASS=0
FAIL=0
WARN=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✅${NC}  $*"; (( PASS++ )); }
fail() { echo -e "  ${RED}❌${NC}  $*"; (( FAIL++ )); }
warn() { echo -e "  ${YELLOW}⚠️ ${NC}  $*"; (( WARN++ )); }
info() { echo -e "  ${CYAN}ℹ️ ${NC}  $*"; }

echo ""
echo "========================================================"
echo " Lab 092 Validator"
echo " Live Right-Sizing with AWS Compute Optimizer"
echo "========================================================"
echo ""

# =============================================================================
# GUARD: Check dependencies
# =============================================================================

for cmd in aws terraform python3; do
  if ! command -v "$cmd" &>/dev/null; then
    echo -e "${RED}ERROR: '$cmd' not found. Cannot validate.${NC}"
    exit 1
  fi
done

# =============================================================================
# GUARD: Terraform state
# =============================================================================

if [ ! -f "terraform.tfstate" ]; then
  echo -e "${RED}ERROR: terraform.tfstate not found.${NC}"
  echo "       Run 'terraform apply' before validating."
  exit 1
fi

# =============================================================================
# READ OUTPUTS
# =============================================================================

PROD_WEB_IDS=( $(terraform output -json prod_web_instance_ids 2>/dev/null \
  | python3 -c "import sys,json; [print(x) for x in json.load(sys.stdin)]") )
DEV_WEB_ID=$(terraform output -raw dev_web_instance_id 2>/dev/null || echo "")
DEV_WORKER_IDS=( $(terraform output -json dev_worker_instance_ids 2>/dev/null \
  | python3 -c "import sys,json; [print(x) for x in json.load(sys.stdin)]") )

ALL_IDS=( "${PROD_WEB_IDS[@]}" "$DEV_WEB_ID" "${DEV_WORKER_IDS[@]}" )

# =============================================================================
# CHECK 1 — Infrastructure deployed
# =============================================================================

echo -e "${BOLD}[1] Infrastructure${NC}"

RUNNING=$(aws ec2 describe-instances \
  --region "$REGION" \
  --instance-ids "${ALL_IDS[@]}" \
  --filters "Name=instance-state-name,Values=running,stopped,pending" \
  --query "length(Reservations[].Instances[])" \
  --output text 2>/dev/null || echo "0")

if [ "$RUNNING" -eq "${#ALL_IDS[@]}" ]; then
  pass "${#ALL_IDS[@]} instances found in AWS"
else
  fail "Expected ${#ALL_IDS[@]} instances, found $RUNNING. Has terraform apply completed?"
fi

# =============================================================================
# CHECK 2 — Prod web servers started as m5.2xlarge
# =============================================================================

echo ""
echo -e "${BOLD}[2] Starting instance types (over-provisioned baseline)${NC}"

for id in "${PROD_WEB_IDS[@]}"; do
  CURRENT_TYPE=$(aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "$id" \
    --query "Reservations[0].Instances[0].InstanceType" \
    --output text 2>/dev/null || echo "unknown")

  NAME=$(aws ec2 describe-tags \
    --region "$REGION" \
    --filters "Name=resource-id,Values=${id}" "Name=key,Values=Name" \
    --query "Tags[0].Value" --output text 2>/dev/null || echo "$id")

  if [[ "$CURRENT_TYPE" == m5.* ]] || [[ "$CURRENT_TYPE" == t3.* ]]; then
    pass "$NAME: instance type is $CURRENT_TYPE (m5 = over-provisioned starting state; t3 = right-sized)"
  else
    fail "$NAME: unexpected instance type $CURRENT_TYPE"
  fi
done

# =============================================================================
# CHECK 3 — CloudWatch metrics present (14 days seeded)
# =============================================================================

echo ""
echo -e "${BOLD}[3] CloudWatch metric history${NC}"

FOURTEEN_DAYS_AGO=$(date -u -d '14 days ago' '+%Y-%m-%dT%H:%M:%S')
NOW=$(date -u '+%Y-%m-%dT%H:%M:%S')

for id in "${ALL_IDS[@]}"; do
  NAME=$(aws ec2 describe-tags \
    --region "$REGION" \
    --filters "Name=resource-id,Values=${id}" "Name=key,Values=Name" \
    --query "Tags[0].Value" --output text 2>/dev/null || echo "$id")

  COUNT=$(aws cloudwatch get-metric-statistics \
    --region "$REGION" \
    --namespace "AWS/EC2" \
    --metric-name "CPUUtilization" \
    --dimensions "Name=InstanceId,Value=${id}" \
    --start-time "$FOURTEEN_DAYS_AGO" \
    --end-time "$NOW" \
    --period 3600 \
    --statistics Average \
    --query "length(Datapoints)" \
    --output text 2>/dev/null || echo "0")

  if [ "$COUNT" -gt 200 ]; then
    pass "$NAME: $COUNT hourly data points in CloudWatch"
  elif [ "$COUNT" -gt 0 ]; then
    warn "$NAME: only $COUNT data points — seeding may be incomplete (expected 336)"
  else
    fail "$NAME: no CloudWatch data found. Has seed-metrics.sh been run?"
  fi
done

# =============================================================================
# CHECK 4 — Compute Optimizer enrolled
# =============================================================================

echo ""
echo -e "${BOLD}[4] Compute Optimizer enrolment${NC}"

STATUS=$(aws compute-optimizer get-enrollment-status \
  --region "$REGION" \
  --query "status" \
  --output text 2>/dev/null || echo "Unknown")

if [ "$STATUS" = "Active" ]; then
  pass "Compute Optimizer: Active"
else
  fail "Compute Optimizer status: $STATUS — run seed-metrics.sh to enrol"
fi

# =============================================================================
# CHECK 5 — At least one instance right-sized (optional — if time has passed)
# =============================================================================

echo ""
echo -e "${BOLD}[5] Right-sizing applied${NC}"

ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text 2>/dev/null || echo "")
ARNS=()
for id in "${ALL_IDS[@]}"; do
  ARNS+=("arn:aws:ec2:${REGION}:${ACCOUNT_ID}:instance/${id}")
done

RECS=$(aws compute-optimizer get-ec2-instance-recommendations \
  --instance-arns "${ARNS[@]}" \
  --region "$REGION" \
  --output json 2>/dev/null || echo '{"instanceRecommendations":[]}')

REC_COUNT=$(echo "$RECS" | python3 -c "
import sys,json; data=json.load(sys.stdin)
print(len(data.get('instanceRecommendations',[])))
" 2>/dev/null || echo "0")

if [ "$REC_COUNT" -eq 0 ]; then
  warn "Compute Optimizer has not generated recommendations yet."
  warn "This is normal — it takes up to 12 hours. Check 5 will pass once they appear."
  info "Run ./scripts/check-recommendations.sh to monitor progress."
else
  # Check if at least one instance has been changed from m5 to t3
  T3_COUNT=0
  for id in "${ALL_IDS[@]}"; do
    TYPE=$(aws ec2 describe-instances \
      --region "$REGION" \
      --instance-ids "$id" \
      --query "Reservations[0].Instances[0].InstanceType" \
      --output text 2>/dev/null || echo "")
    if [[ "$TYPE" == t3.* ]]; then
      T3_COUNT=$(( T3_COUNT + 1 ))
    fi
  done

  if [ "$T3_COUNT" -gt 0 ]; then
    pass "$T3_COUNT instance(s) have been right-sized to t3 family"
  else
    warn "Recommendations are available but no instances have been right-sized yet."
    warn "Continue to Step 8 of the solution file to apply a recommendation."
  fi
fi

# =============================================================================
# SUMMARY
# =============================================================================

echo ""
echo "========================================================"
TOTAL=$(( PASS + FAIL + WARN ))
echo -e " Results: ${GREEN}${PASS} passed${NC}  ${RED}${FAIL} failed${NC}  ${YELLOW}${WARN} warnings${NC}"
echo "========================================================"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo -e "${RED} Some checks failed. Review the output above.${NC}"
  echo ""
  exit 1
elif [ "$WARN" -gt 0 ]; then
  echo -e "${YELLOW} Lab is progressing correctly — some steps require waiting.${NC}"
  echo -e "${YELLOW} Re-run this validator after Compute Optimizer processes your data.${NC}"
  echo ""
  exit 0
else
  echo -e "${GREEN} All checks passed. Lab 092 complete.${NC}"
  echo ""
  echo " Remember to run: terraform destroy"
  echo ""
  exit 0
fi
