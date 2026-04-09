#!/bin/bash
# =============================================================================
# scripts/seed-metrics.sh — Lab 092
#
# Pushes 14 days of simulated CPUUtilization data into CloudWatch for every
# EC2 instance in this lab. This gives AWS Compute Optimizer enough history
# to generate right-sizing recommendations immediately.
#
# HOW BACKDATING WORKS:
#   aws cloudwatch put-metric-data accepts timestamps up to 14 days in the
#   past. We loop backwards through 336 hours and post one data point per
#   hour. CloudWatch stores them as if the instances had been running and
#   reporting the whole time. Compute Optimizer reads this history and cannot
#   distinguish between real and seeded data.
#
# CPU PROFILES:
#   Each instance group gets a realistic low-utilisation profile that reflects
#   what over-provisioned hardware actually looks like in CloudWatch:
#
#   prod_web  (m5.2xlarge)  →  5–12% CPU  — web server doing almost nothing
#   dev_web   (m5.xlarge)   →  2–7%  CPU  — barely used dev box
#   dev_worker (m5.xlarge)  →  3–8%  CPU  — light background jobs
#
#   All values are well below the AWS 40% right-sizing threshold.
#
# RUNTIME: approximately 60–90 seconds for all 5 instances.
#
# USAGE:
#   Run from the lab-092 directory AFTER terraform apply:
#   ./scripts/seed-metrics.sh
# =============================================================================

set -euo pipefail

REGION="eu-west-2"
DAYS=14
HOURS=$(( DAYS * 24 ))   # 336 data points per instance

# Colours for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()    { echo -e "${CYAN}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; }

echo ""
echo "========================================================"
echo " Lab 092 — CloudWatch Metric Seeder"
echo " Simulating 14 days of CPU utilisation history"
echo "========================================================"
echo ""

# =============================================================================
# STEP 1 — Verify we are in the right directory and Terraform state exists
# =============================================================================

if [ ! -f "main.tf" ]; then
  error "main.tf not found. Run this script from the lab-092 directory."
  exit 1
fi

if [ ! -f "terraform.tfstate" ]; then
  error "terraform.tfstate not found."
  error "Have you run 'terraform apply' yet?"
  exit 1
fi

info "Terraform state found."

# =============================================================================
# STEP 2 — Read instance IDs from Terraform outputs
#
# We use 'terraform output' rather than hardcoding IDs. This is important
# because instance IDs change every time you destroy and re-apply.
# =============================================================================

info "Reading instance IDs from Terraform outputs..."
echo ""

PROD_WEB_IDS_RAW=$(terraform output -json prod_web_instance_ids 2>/dev/null)
DEV_WEB_ID=$(terraform output -raw dev_web_instance_id 2>/dev/null)
DEV_WORKER_IDS_RAW=$(terraform output -json dev_worker_instance_ids 2>/dev/null)

# Parse JSON arrays into bash arrays using Python (available on Amazon Linux)
PROD_WEB_IDS=( $(echo "$PROD_WEB_IDS_RAW" | python3 -c "import sys,json; [print(x) for x in json.load(sys.stdin)]") )
DEV_WORKER_IDS=( $(echo "$DEV_WORKER_IDS_RAW" | python3 -c "import sys,json; [print(x) for x in json.load(sys.stdin)]") )

# Validate we got IDs
if [ ${#PROD_WEB_IDS[@]} -eq 0 ] || [ -z "$DEV_WEB_ID" ] || [ ${#DEV_WORKER_IDS[@]} -eq 0 ]; then
  error "Could not read instance IDs from Terraform outputs."
  error "Try running: terraform output"
  exit 1
fi

echo "  Production web servers:"
for id in "${PROD_WEB_IDS[@]}"; do
  echo "    $id  (m5.2xlarge)"
done
echo ""
echo "  Dev web server:"
echo "    $DEV_WEB_ID  (m5.xlarge)"
echo ""
echo "  Dev workers:"
for id in "${DEV_WORKER_IDS[@]}"; do
  echo "    $id  (m5.xlarge)"
done
echo ""

# =============================================================================
# STEP 3 — Verify instances are actually running in AWS
#
# Terraform state tells us IDs but doesn't guarantee they're still running.
# =============================================================================

info "Verifying instances are running in AWS..."

ALL_IDS=( "${PROD_WEB_IDS[@]}" "$DEV_WEB_ID" "${DEV_WORKER_IDS[@]}" )
INSTANCE_ID_LIST=$(IFS=','; echo "${ALL_IDS[*]}")

RUNNING_COUNT=$(aws ec2 describe-instances \
  --region "$REGION" \
  --instance-ids "${ALL_IDS[@]}" \
  --filters "Name=instance-state-name,Values=running,pending,stopped" \
  --query "length(Reservations[].Instances[])" \
  --output text 2>/dev/null || echo "0")

EXPECTED=${#ALL_IDS[@]}

if [ "$RUNNING_COUNT" -ne "$EXPECTED" ]; then
  warn "Expected $EXPECTED instances, found $RUNNING_COUNT in AWS."
  warn "Some instances may not have finished launching yet. Wait 30 seconds and retry."
  exit 1
fi

success "All $EXPECTED instances confirmed in AWS."
echo ""

# =============================================================================
# STEP 4 — CPU profile functions
#
# Each function accepts an hour offset (0 = now, 335 = 14 days ago) and
# returns a float CPU percentage. The hour_of_day calculation creates a
# realistic pattern where utilisation is slightly higher during business
# hours, but still well below the 40% AWS right-sizing threshold.
# =============================================================================

# Web servers: 5–12% during business hours, 3–6% overnight
cpu_web() {
  local offset=$1
  local hour_of_day=$(( offset % 24 ))
  if [ "$hour_of_day" -ge 7 ] && [ "$hour_of_day" -le 19 ]; then
    local base=$(( 6 + RANDOM % 6 ))
    local frac=$(( RANDOM % 10 ))
    echo "${base}.${frac}"
  else
    local base=$(( 3 + RANDOM % 3 ))
    local frac=$(( RANDOM % 10 ))
    echo "${base}.${frac}"
  fi
}

# Dev instances: 2–7% during work hours, 1–3% overnight/weekends
cpu_dev() {
  local offset=$1
  local hour_of_day=$(( offset % 24 ))
  # Rough weekday check: offsets 0-4 and 168-335 would be weekend territory
  # Simplified: just use time of day as a proxy
  if [ "$hour_of_day" -ge 9 ] && [ "$hour_of_day" -le 17 ]; then
    local base=$(( 4 + RANDOM % 4 ))
    local frac=$(( RANDOM % 10 ))
    echo "${base}.${frac}"
  else
    local base=$(( 1 + RANDOM % 2 ))
    local frac=$(( RANDOM % 10 ))
    echo "${base}.${frac}"
  fi
}

# =============================================================================
# STEP 5 — Core seeding function
#
# Builds JSON batches of 20 data points (the CloudWatch API maximum per call)
# and pushes them. Batching reduces API calls from 336 to 17 per instance,
# cutting runtime from ~5 minutes to ~15 seconds per instance.
# =============================================================================

seed_instance() {
  local instance_id="$1"
  local profile="$2"     # "web" or "dev"
  local label="$3"

  echo -n "  Seeding $label ($instance_id) ... "

  local now
  now=$(date +%s)

  local batch='['
  local count=0
  local total=0

  for (( h=HOURS; h>=1; h-- )); do
    local ts=$(( now - (h * 3600) ))

    # Generate ISO8601 timestamp — compatible with both GNU date (Linux) and
    # BSD date (macOS). The Pi uses GNU date.
    local iso
    iso=$(date -u -d "@${ts}" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null \
      || date -u -r "${ts}" '+%Y-%m-%dT%H:%M:%S')

    # Get CPU value for this hour
    local cpu
    if [ "$profile" = "web" ]; then
      cpu=$(cpu_web "$h")
    else
      cpu=$(cpu_dev "$h")
    fi

    # Append to batch (comma-separate after first item)
    if [ "$count" -gt 0 ]; then
      batch+=','
    fi
    batch+="{\"MetricName\":\"CPUUtilization\",\"Dimensions\":[{\"Name\":\"InstanceId\",\"Value\":\"${instance_id}\"}],\"Timestamp\":\"${iso}\",\"Value\":${cpu},\"Unit\":\"Percent\"}"
    count=$(( count + 1 ))
    total=$(( total + 1 ))

    # Flush batch at 20 items or on the final data point
    if [ "$count" -eq 20 ] || [ "$h" -eq 1 ]; then
      batch+=']'
      aws cloudwatch put-metric-data \
        --region "$REGION" \
        --namespace "AWS/EC2" \
        --metric-data "$batch" \
        --no-cli-pager \
        > /dev/null 2>&1
      batch='['
      count=0
    fi
  done

  success "$total data points pushed"
}

# =============================================================================
# STEP 6 — Run the seeder for every instance
# =============================================================================

info "Seeding CloudWatch metrics (this takes ~60–90 seconds)..."
echo ""

for id in "${PROD_WEB_IDS[@]}"; do
  NAME=$(aws ec2 describe-tags \
    --region "$REGION" \
    --filters "Name=resource-id,Values=${id}" "Name=key,Values=Name" \
    --query "Tags[0].Value" \
    --output text 2>/dev/null || echo "$id")
  seed_instance "$id" "web" "$NAME"
done

seed_instance "$DEV_WEB_ID" "dev" "dev-web"

for id in "${DEV_WORKER_IDS[@]}"; do
  NAME=$(aws ec2 describe-tags \
    --region "$REGION" \
    --filters "Name=resource-id,Values=${id}" "Name=key,Values=Name" \
    --query "Tags[0].Value" \
    --output text 2>/dev/null || echo "$id")
  seed_instance "$id" "dev" "$NAME"
done

echo ""
info "Total data points pushed: $(( HOURS * ${#ALL_IDS[@]} ))"

# =============================================================================
# STEP 7 — Opt in to AWS Compute Optimizer
#
# This is account-level and idempotent — safe to run multiple times.
# After opting in, Compute Optimizer begins analysing the CloudWatch history.
# Recommendations typically appear within 12 hours, sometimes faster.
# =============================================================================

echo ""
info "Enabling AWS Compute Optimizer for this account..."

aws compute-optimizer update-enrollment-status \
  --status Active \
  --region "$REGION" \
  --no-cli-pager > /dev/null 2>&1 \
  && success "Compute Optimizer enrolled." \
  || warn "Compute Optimizer may already be enrolled — this is fine."

# =============================================================================
# STEP 8 — Verify CloudWatch data landed
# =============================================================================

echo ""
info "Verifying metric data in CloudWatch (sample check on first instance)..."

SAMPLE_ID="${ALL_IDS[0]}"
FOURTEEN_DAYS_AGO=$(date -u -d '14 days ago' '+%Y-%m-%dT%H:%M:%S')
NOW=$(date -u '+%Y-%m-%dT%H:%M:%S')

DATAPOINT_COUNT=$(aws cloudwatch get-metric-statistics \
  --region "$REGION" \
  --namespace "AWS/EC2" \
  --metric-name "CPUUtilization" \
  --dimensions "Name=InstanceId,Value=${SAMPLE_ID}" \
  --start-time "$FOURTEEN_DAYS_AGO" \
  --end-time "$NOW" \
  --period 3600 \
  --statistics Average \
  --query "length(Datapoints)" \
  --output text 2>/dev/null || echo "0")

if [ "$DATAPOINT_COUNT" -gt 100 ]; then
  success "CloudWatch confirmed: $DATAPOINT_COUNT data points visible for $SAMPLE_ID"
else
  warn "Only $DATAPOINT_COUNT data points visible — CloudWatch may need a minute to index."
  warn "Wait 60 seconds and check again with: ./scripts/check-recommendations.sh"
fi

# =============================================================================
# SUMMARY
# =============================================================================

echo ""
echo "========================================================"
echo " Seeding complete."
echo "========================================================"
echo ""
echo " What happens next:"
echo ""
echo "   Compute Optimizer will analyse your CloudWatch history."
echo "   Recommendations typically appear within 12 hours."
echo "   Check progress with:"
echo ""
echo "   ./scripts/check-recommendations.sh"
echo ""
echo " While you wait, read the solution file for Step 6 onward"
echo " so you know how to interpret the output when it arrives."
echo ""
