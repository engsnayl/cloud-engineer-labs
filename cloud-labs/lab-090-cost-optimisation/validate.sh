#!/bin/bash

# =============================================================================
# Lab 090 Validation — Cost Optimisation & Right-Sizing
# =============================================================================

PASS=0
FAIL=0
TOTAL=0

check() {
    local description="$1"
    local result="$2"
    ((TOTAL++))
    if [[ "$result" == "0" ]]; then
        echo -e "  \033[32m✅  $description\033[0m"
        ((PASS++))
    else
        echo -e "  \033[31m❌  $description\033[0m"
        ((FAIL++))
    fi
}

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   Lab 090: Cost Optimisation — Validation               ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

MAIN="main.tf"

if [[ ! -f "$MAIN" ]]; then
    echo "  ❌  main.tf not found — are you in the right directory?"
    exit 1
fi

# -------------------------------------------------------------------------
# 1. Terraform syntax valid
# -------------------------------------------------------------------------
echo "── Terraform Syntax ──"
terraform validate &>/dev/null
check "terraform validate passes" "$?"

# -------------------------------------------------------------------------
# 2. EC2 Right-Sizing — prod web servers should be smaller than m5.2xlarge
# -------------------------------------------------------------------------
echo ""
echo "── EC2 Right-Sizing ──"

prod_type=$(grep -A 5 'aws_instance.*prod_web' "$MAIN" | grep 'instance_type' | head -1 | grep -o '"[^"]*"' | tr -d '"')
if [[ "$prod_type" != "m5.2xlarge" && -n "$prod_type" ]]; then
    check "Production web servers right-sized (was m5.2xlarge, now $prod_type)" "0"
else
    check "Production web servers right-sized (still m5.2xlarge)" "1"
fi

dev_type=$(grep -A 5 'aws_instance.*dev_web' "$MAIN" | grep 'instance_type' | head -1 | grep -o '"[^"]*"' | tr -d '"')
if [[ "$dev_type" != "m5.xlarge" && -n "$dev_type" ]]; then
    check "Dev web servers right-sized (was m5.xlarge, now $dev_type)" "0"
else
    check "Dev web servers right-sized (still m5.xlarge)" "1"
fi

# Check prod disk sizes reduced
prod_disk=$(grep -A 10 'aws_instance.*prod_web' "$MAIN" | grep -A 3 'root_block_device' | grep 'volume_size' | head -1 | grep -o '[0-9]*')
if [[ -n "$prod_disk" && "$prod_disk" -lt 200 ]]; then
    check "Production disk reduced from 200GB (now ${prod_disk}GB)" "0"
else
    check "Production disk reduced from 200GB" "1"
fi

# -------------------------------------------------------------------------
# 3. RDS Right-Sizing
# -------------------------------------------------------------------------
echo ""
echo "── RDS Right-Sizing ──"

rds_class=$(grep -A 15 'aws_db_instance.*main' "$MAIN" | grep 'instance_class' | grep -o '"[^"]*"' | tr -d '"')
if [[ "$rds_class" != "db.r5.2xlarge" && -n "$rds_class" ]]; then
    check "RDS instance right-sized (was db.r5.2xlarge, now $rds_class)" "0"
else
    check "RDS instance right-sized (still db.r5.2xlarge)" "1"
fi

rds_storage_type=$(grep -A 15 'aws_db_instance.*main' "$MAIN" | grep 'storage_type' | grep -o '"[^"]*"' | tr -d '"')
if [[ "$rds_storage_type" != "io1" ]]; then
    check "RDS storage type changed from io1 (now $rds_storage_type)" "0"
else
    check "RDS storage type changed from io1" "1"
fi

# -------------------------------------------------------------------------
# 4. S3 Lifecycle Policies
# -------------------------------------------------------------------------
echo ""
echo "── S3 Lifecycle Policies ──"

grep -q 'aws_s3_bucket_lifecycle_configuration' "$MAIN"
check "At least one S3 lifecycle policy exists" "$?"

grep -A 20 'aws_s3_bucket_lifecycle_configuration' "$MAIN" | grep -q 'logs'
check "Lifecycle policy covers logs bucket" "$?"

grep -A 20 'aws_s3_bucket_lifecycle_configuration' "$MAIN" | grep -q 'dev.artifact\|dev_artifact'
check "Lifecycle policy covers dev artifacts bucket" "$?"

# -------------------------------------------------------------------------
# 5. Cost Allocation Tags
# -------------------------------------------------------------------------
echo ""
echo "── Cost Allocation Tags ──"

grep -q 'Environment' "$MAIN"
check "Environment tag present on resources" "$?"

grep -q 'Team' "$MAIN"
check "Team tag present on resources" "$?"

grep -q 'CostCentre\|CostCenter' "$MAIN"
check "CostCentre tag present on resources" "$?"

# -------------------------------------------------------------------------
# 6. Billing Alarm
# -------------------------------------------------------------------------
echo ""
echo "── Billing Controls ──"

grep -q 'aws_cloudwatch_metric_alarm\|aws_budgets_budget' "$MAIN"
check "Billing alarm or budget alert configured" "$?"

# -------------------------------------------------------------------------
# 7. Security Fixes (bonus — not cost but should be flagged)
# -------------------------------------------------------------------------
echo ""
echo "── Security (Bonus) ──"

dev_sg_open=$(grep -A 10 'aws_security_group.*dev' "$MAIN" | grep -c '0.0.0.0/0')
if [[ "$dev_sg_open" -lt 2 ]]; then
    check "Dev security group no longer wide open to internet" "0"
else
    check "Dev security group no longer wide open to internet" "1"
fi

db_sg_open=$(grep -A 10 'aws_security_group.*db' "$MAIN" | grep 'cidr_blocks' | grep -c '0.0.0.0/0')
if [[ "$db_sg_open" -eq 0 ]]; then
    check "Database security group restricted (not open to 0.0.0.0/0)" "0"
else
    check "Database security group restricted (not open to 0.0.0.0/0)" "1"
fi

# -------------------------------------------------------------------------
# Results
# -------------------------------------------------------------------------
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ "$FAIL" -eq 0 ]]; then
    echo ""
    echo "  ✅  ALL $TOTAL CHECKS PASSED"
    echo ""
    echo "  Well done — you've identified and fixed the waste."
    echo "  In a real engagement, this kind of review typically"
    echo "  saves companies 30-50% on their monthly AWS bill."
    echo ""
else
    echo ""
    echo "  ⚠️   $PASS of $TOTAL checks passed ($FAIL remaining)"
    echo ""
    echo "  Keep going — review HINTS.md if you're stuck."
    echo ""
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
