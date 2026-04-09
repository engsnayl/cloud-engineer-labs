#!/bin/bash
# =============================================================================
# scripts/check-recommendations.sh — Lab 092
#
# Polls AWS Compute Optimizer for EC2 right-sizing recommendations.
# Run this after seed-metrics.sh — recommendations typically appear within
# 12 hours of Compute Optimizer being enrolled.
#
# USAGE:
#   ./scripts/check-recommendations.sh
#
# Run repeatedly until recommendations appear. The script tells you clearly
# what state each instance is in and what to do next.
# =============================================================================

set -euo pipefail

REGION="eu-west-2"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WAIT]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

echo ""
echo "========================================================"
echo " Lab 092 — Compute Optimizer Recommendation Check"
echo "========================================================"
echo ""

# Verify enrolment status first
ENROLMENT_STATUS=$(aws compute-optimizer get-enrollment-status \
  --region "$REGION" \
  --query "status" \
  --output text 2>/dev/null || echo "Unknown")

if [ "$ENROLMENT_STATUS" != "Active" ]; then
  error "Compute Optimizer status: $ENROLMENT_STATUS"
  error "Run seed-metrics.sh first to enrol and seed data."
  exit 1
fi

success "Compute Optimizer status: Active"
echo ""

# Read all instance IDs from Terraform outputs
if [ ! -f "terraform.tfstate" ]; then
  error "terraform.tfstate not found. Run from the lab-092 directory."
  exit 1
fi

ALL_IDS_JSON=$(terraform output -json all_instance_ids 2>/dev/null)
ALL_IDS=( $(echo "$ALL_IDS_JSON" | python3 -c "import sys,json; [print(x) for x in json.load(sys.stdin)]") )

if [ ${#ALL_IDS[@]} -eq 0 ]; then
  error "Could not read instance IDs. Has terraform apply completed?"
  exit 1
fi

info "Fetching recommendations for ${#ALL_IDS[@]} instances..."
echo ""

# Build ARN list for the API call
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text 2>/dev/null)

ARNS=()
for id in "${ALL_IDS[@]}"; do
  ARNS+=("arn:aws:ec2:${REGION}:${ACCOUNT_ID}:instance/${id}")
done

# Fetch recommendations
RECOMMENDATIONS=$(aws compute-optimizer get-ec2-instance-recommendations \
  --instance-arns "${ARNS[@]}" \
  --region "$REGION" \
  --output json 2>/dev/null || echo '{"instanceRecommendations":[],"errors":[]}')

REC_COUNT=$(echo "$RECOMMENDATIONS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(len(data.get('instanceRecommendations', [])))
" 2>/dev/null || echo "0")

ERROR_COUNT=$(echo "$RECOMMENDATIONS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(len(data.get('errors', [])))
" 2>/dev/null || echo "0")

# Display results
if [ "$REC_COUNT" -eq 0 ]; then
  warn "No recommendations yet. Compute Optimizer is still processing."
  warn ""
  warn "This is normal — it typically takes up to 12 hours after enrolment."
  warn "Come back later and re-run this script."
  echo ""

  if [ "$ERROR_COUNT" -gt 0 ]; then
    info "Errors from Compute Optimizer API:"
    echo "$RECOMMENDATIONS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for err in data.get('errors', []):
    print(f\"  {err.get('identifier','?')} — {err.get('message','?')}\")
"
  fi

  echo ""
  info "While you wait, you can verify CloudWatch data is present:"
  echo ""
  echo "   aws cloudwatch get-metric-statistics \\"
  echo "     --region $REGION \\"
  echo "     --namespace AWS/EC2 \\"
  echo "     --metric-name CPUUtilization \\"
  echo "     --dimensions Name=InstanceId,Value=${ALL_IDS[0]} \\"
  echo "     --start-time \$(date -u -d '14 days ago' '+%Y-%m-%dT%H:%M:%S') \\"
  echo "     --end-time \$(date -u '+%Y-%m-%dT%H:%M:%S') \\"
  echo "     --period 86400 \\"
  echo "     --statistics Average Maximum \\"
  echo "     --output table"
  echo ""
  exit 0
fi

# Recommendations are available — format them nicely
success "$REC_COUNT recommendation(s) available."
echo ""
printf "${BOLD}%-22s %-18s %-14s %-14s %-12s${NC}\n" \
  "Instance ID" "Finding" "Current Type" "Recommended" "Est. Saving/mo"
printf "%s\n" "$(printf '%.0s-' {1..80})"

echo "$RECOMMENDATIONS" | python3 -c "
import sys, json

data = json.load(sys.stdin)
for rec in data.get('instanceRecommendations', []):
    instance_id = rec['instanceArn'].split('/')[-1]
    finding     = rec.get('finding', 'N/A')
    current     = rec.get('currentInstanceType', 'N/A')

    options = rec.get('recommendationOptions', [])
    if options:
        top = options[0]
        recommended = top.get('instanceType', 'N/A')
        savings_info = top.get('savingsOpportunity', {})
        savings_val  = savings_info.get('estimatedMonthlySavings', {}).get('value', 0)
        savings_str  = f'\${savings_val:.2f}' if savings_val else 'N/A'
    else:
        recommended = 'N/A'
        savings_str = 'N/A'

    # Colour the finding
    if finding == 'OVER_PROVISIONED':
        colour = '\033[1;33m'
    elif finding == 'OPTIMIZED':
        colour = '\033[0;32m'
    elif finding == 'NOT_ENOUGH_DATA':
        colour = '\033[0;36m'
    else:
        colour = '\033[0m'
    reset = '\033[0m'

    print(f'{instance_id:<22} {colour}{finding:<18}{reset} {current:<14} {recommended:<14} {savings_str}')
"

echo ""

# Check if any instance still shows NOT_ENOUGH_DATA
NOT_ENOUGH=$(echo "$RECOMMENDATIONS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
count = sum(1 for r in data.get('instanceRecommendations',[]) if r.get('finding') == 'NOT_ENOUGH_DATA')
print(count)
" 2>/dev/null || echo "0")

if [ "$NOT_ENOUGH" -gt 0 ]; then
  warn "$NOT_ENOUGH instance(s) still show NOT_ENOUGH_DATA."
  warn "Compute Optimizer needs more time to process the CloudWatch history."
  warn "Re-run this script in 1–2 hours."
  echo ""
fi

OVER=$(echo "$RECOMMENDATIONS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
count = sum(1 for r in data.get('instanceRecommendations',[]) if r.get('finding') == 'OVER_PROVISIONED')
print(count)
" 2>/dev/null || echo "0")

if [ "$OVER" -gt 0 ]; then
  echo ""
  info "$OVER instance(s) flagged as OVER_PROVISIONED."
  info "Continue to Step 8 of the solution file to apply a recommendation."
  echo ""
  echo " Quick reference — apply right-sizing to one instance:"
  echo ""
  echo "   # Get instance ID of dev-web"
  DEV_WEB=$(terraform output -raw dev_web_instance_id 2>/dev/null || echo "<dev-web-instance-id>")
  echo "   INSTANCE_ID=$DEV_WEB"
  echo ""
  echo "   # Stop it"
  echo "   aws ec2 stop-instances --instance-ids \$INSTANCE_ID --region $REGION"
  echo "   aws ec2 wait instance-stopped --instance-ids \$INSTANCE_ID --region $REGION"
  echo ""
  echo "   # Change type to the recommended value"
  echo "   aws ec2 modify-instance-attribute \\"
  echo "     --instance-id \$INSTANCE_ID \\"
  echo "     --instance-type '{\"Value\": \"t3.small\"}' \\"
  echo "     --region $REGION"
  echo ""
  echo "   # Restart"
  echo "   aws ec2 start-instances --instance-ids \$INSTANCE_ID --region $REGION"
  echo "   aws ec2 wait instance-running --instance-ids \$INSTANCE_ID --region $REGION"
  echo ""
fi
