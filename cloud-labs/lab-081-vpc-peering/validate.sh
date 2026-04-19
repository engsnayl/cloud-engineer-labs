#!/bin/bash
# Lab 081 — VPC Peering Validation
# Checks actual resource relationships in main.tf, not just syntax.
# terraform validate and plan pass on broken configs here (overlapping CIDRs
# and missing routes are semantic issues, not syntax errors), so we parse
# the .tf file directly for the learning signals we actually care about.

echo "Running Lab 081 validation..."
echo ""

PASS=0
FAIL=0
TF_FILE="main.tf"

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

if [[ ! -f "$TF_FILE" ]]; then
    echo "ERROR: $TF_FILE not found. Run this script from the lab directory."
    exit 1
fi

# --- Baseline Terraform checks ---
terraform validate &>/dev/null
check "Terraform configuration is syntactically valid" "$?"

terraform plan -detailed-exitcode &>/dev/null
plan_exit=$?
[[ "$plan_exit" -ne 1 ]]
check "Terraform plan completes without errors" "$?"

# --- Bug 1: VPC CIDRs must not overlap ---
# Extract cidr_block values from aws_vpc resources only.
# awk walks the file, tracks when we're inside an aws_vpc block,
# and prints cidr_block lines it finds inside that block.
app_cidr=$(awk '/resource "aws_vpc" "app"/,/^}/' "$TF_FILE" | grep -E 'cidr_block\s*=' | head -1 | grep -oE '"[0-9./]+"' | tr -d '"')
db_cidr=$(awk '/resource "aws_vpc" "db"/,/^}/' "$TF_FILE" | grep -E 'cidr_block\s*=' | head -1 | grep -oE '"[0-9./]+"' | tr -d '"')

if [[ -n "$app_cidr" && -n "$db_cidr" && "$app_cidr" != "$db_cidr" ]]; then
    check "VPC CIDR blocks are unique (no overlap)" "0"
else
    check "VPC CIDR blocks are unique (no overlap)  [app=$app_cidr  db=$db_cidr]" "1"
fi

# --- Bug 2a: App route table has a peering route ---
# Look inside the aws_route_table.app block for a vpc_peering_connection_id reference.
app_rt_has_peering=$(awk '/resource "aws_route_table" "app"/,/^}/' "$TF_FILE" | grep -c 'vpc_peering_connection_id')
[[ "$app_rt_has_peering" -ge 1 ]]
check "App VPC route table contains a peering route" "$?"

# --- Bug 2b: DB route table has a peering route ---
db_rt_has_peering=$(awk '/resource "aws_route_table" "db"/,/^}/' "$TF_FILE" | grep -c 'vpc_peering_connection_id')
[[ "$db_rt_has_peering" -ge 1 ]]
check "DB VPC route table contains a peering route" "$?"

# --- Bug 2c: Route tables are associated with their subnets ---
# Without associations, routes exist but aren't used by subnet traffic.
has_app_assoc=$(awk '/resource "aws_route_table_association" "app"/,/^}/' "$TF_FILE" | grep -c 'aws_subnet.app')
has_db_assoc=$(awk '/resource "aws_route_table_association" "db"/,/^}/' "$TF_FILE" | grep -c 'aws_subnet.db')
[[ "$has_app_assoc" -ge 1 && "$has_db_assoc" -ge 1 ]]
check "Subnets are associated with their route tables" "$?"

# --- Bug 3: DB security group ingress references the APP VPC CIDR, not its own ---
# After fixing Bug 1, the app and db CIDRs differ. The db SG should allow
# ingress from the app CIDR specifically. If it still references its own
# CIDR (or the old overlapping value), cross-VPC traffic won't be permitted.
db_sg_cidr=$(awk '/resource "aws_security_group" "db"/,/^}/' "$TF_FILE" | grep 'cidr_blocks' | grep -oE '"[0-9./]+"' | tr -d '"' | head -1)

if [[ -n "$app_cidr" && "$db_sg_cidr" == "$app_cidr" ]]; then
    check "DB security group allows ingress from app VPC CIDR" "0"
else
    check "DB security group allows ingress from app VPC CIDR  [expected=$app_cidr  found=$db_sg_cidr]" "1"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
