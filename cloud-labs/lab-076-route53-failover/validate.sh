#!/bin/bash
# =============================================================================
# Lab 076 — Route 53 DNS Failover Not Working
# validate.sh — Checks the actual deployed AWS state, not just Terraform syntax
# Run AFTER: terraform apply
# =============================================================================

PASS=0
FAIL=0
WARN=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

check() {
    local description="$1"
    local result="$2"
    if [[ "$result" == "0" ]]; then
        echo -e "  ${GREEN}✅${NC}  $description"
        ((PASS++))
    else
        echo -e "  ${RED}❌${NC}  $description"
        ((FAIL++))
    fi
}

warn() {
    local description="$1"
    echo -e "  ${YELLOW}⚠️ ${NC}  $description"
    ((WARN++))
}

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          Lab 076 — Route 53 DNS Failover Validator           ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# =============================================================================
# SECTION 1: Terraform syntax checks
# =============================================================================
echo -e "${WHITE}── Section 1: Terraform Configuration ──────────────────────────${NC}"

terraform validate &>/dev/null
check "Terraform configuration is valid (no syntax errors)" "$?"

terraform plan -detailed-exitcode &>/dev/null
plan_exit=$?
[[ "$plan_exit" -ne 1 ]]
check "Terraform plan completes without errors" "$?"

# =============================================================================
# SECTION 2: Check Terraform state exists (apply has been run)
# =============================================================================
echo ""
echo -e "${WHITE}── Section 2: Deployed State ────────────────────────────────────${NC}"

if ! terraform show &>/dev/null; then
    echo -e "  ${RED}❌  No Terraform state found — have you run 'terraform apply'?${NC}"
    echo ""
    echo -e "${RED}Cannot continue without deployed state. Run: terraform apply -auto-approve${NC}"
    exit 1
fi

# Pull outputs we need
ZONE_ID=$(terraform output -raw zone_id 2>/dev/null)
HEALTH_CHECK_ID=$(terraform output -raw health_check_id 2>/dev/null)

if [[ -z "$ZONE_ID" ]]; then
    echo -e "  ${RED}❌  Could not read zone_id from Terraform outputs.${NC}"
    warn "Make sure your main.tf has: output \"zone_id\" { value = aws_route53_zone.main.zone_id }"
    ZONE_ID_MISSING=1
fi

if [[ -z "$HEALTH_CHECK_ID" ]]; then
    echo -e "  ${RED}❌  Could not read health_check_id from Terraform outputs.${NC}"
    warn "Make sure your main.tf has: output \"health_check_id\" { value = aws_route53_health_check.primary.id }"
    HEALTH_CHECK_ID_MISSING=1
fi

# =============================================================================
# SECTION 3: Health check validation (AWS CLI)
# =============================================================================
echo ""
echo -e "${WHITE}── Section 3: Health Check Configuration ────────────────────────${NC}"

if [[ -z "$HEALTH_CHECK_ID_MISSING" ]]; then
    HC_JSON=$(aws route53 get-health-check --health-check-id "$HEALTH_CHECK_ID" --output json 2>/dev/null)

    if [[ -z "$HC_JSON" ]]; then
        check "Health check exists in AWS" "1"
    else
        check "Health check exists in AWS" "0"

        # Port check
        HC_PORT=$(echo "$HC_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['HealthCheck']['HealthCheckConfig']['Port'])" 2>/dev/null)
        [[ "$HC_PORT" == "80" ]]
        check "Health check port is 80 (not 8080 or other)" "$?"
        if [[ "$HC_PORT" != "80" ]]; then
            echo -e "       ${YELLOW}Found port: $HC_PORT — should be 80${NC}"
        fi

        # Protocol check
        HC_TYPE=$(echo "$HC_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['HealthCheck']['HealthCheckConfig']['Type'])" 2>/dev/null)
        [[ "$HC_TYPE" == "HTTP" ]]
        check "Health check protocol is HTTP" "$?"

        # Path check
        HC_PATH=$(echo "$HC_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin)['HealthCheck']['HealthCheckConfig']['ResourcePath'])" 2>/dev/null)
        [[ "$HC_PATH" == "/health" ]]
        check "Health check path is /health" "$?"
    fi
else
    warn "Skipping health check AWS validation — health_check_id output missing"
fi

# =============================================================================
# SECTION 4: DNS record validation (AWS CLI)
# =============================================================================
echo ""
echo -e "${WHITE}── Section 4: DNS Record Configuration ──────────────────────────${NC}"

if [[ -z "$ZONE_ID_MISSING" ]]; then
    RECORDS_JSON=$(aws route53 list-resource-record-sets --hosted-zone-id "$ZONE_ID" --output json 2>/dev/null)

    if [[ -z "$RECORDS_JSON" ]]; then
        check "Hosted zone accessible and records retrievable" "1"
    else
        check "Hosted zone accessible and records retrievable" "0"

        # Extract the A records for app.example-internal.com
        APP_RECORDS=$(echo "$RECORDS_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
records = [r for r in data['ResourceRecordSets'] if r['Name'].startswith('app.example-internal.com') and r['Type'] == 'A']
print(json.dumps(records))
" 2>/dev/null)

        RECORD_COUNT=$(echo "$APP_RECORDS" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null)

        [[ "$RECORD_COUNT" == "2" ]]
        check "Two A records exist for app.example-internal.com (primary + secondary)" "$?"
        if [[ "$RECORD_COUNT" != "2" ]]; then
            echo -e "       ${YELLOW}Found $RECORD_COUNT record(s) — expected 2${NC}"
        fi

        # Check PRIMARY record
        PRIMARY_RECORD=$(echo "$APP_RECORDS" | python3 -c "
import sys, json
records = json.load(sys.stdin)
primary = [r for r in records if r.get('Failover') == 'PRIMARY']
print(json.dumps(primary[0]) if primary else '{}')
" 2>/dev/null)

        [[ "$PRIMARY_RECORD" != "{}" ]]
        check "Primary record has failover_routing_policy type = PRIMARY" "$?"

        if [[ "$PRIMARY_RECORD" != "{}" ]]; then
            # Primary set_identifier
            PRIMARY_ID=$(echo "$PRIMARY_RECORD" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('SetIdentifier',''))" 2>/dev/null)
            [[ -n "$PRIMARY_ID" ]]
            check "Primary record has set_identifier set" "$?"

            # Primary health check linked
            PRIMARY_HC=$(echo "$PRIMARY_RECORD" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('HealthCheckId',''))" 2>/dev/null)
            [[ -n "$PRIMARY_HC" ]]
            check "Primary record has health_check_id linked" "$?"
            if [[ -z "$PRIMARY_HC" ]]; then
                echo -e "       ${YELLOW}health_check_id is missing from the PRIMARY record${NC}"
            fi

            # Primary TTL
            PRIMARY_TTL=$(echo "$PRIMARY_RECORD" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('TTL','9999'))" 2>/dev/null)
            [[ "$PRIMARY_TTL" -le 60 ]] 2>/dev/null
            check "Primary record TTL is 60 seconds or less (was: ${PRIMARY_TTL}s)" "$?"
            if [[ "$PRIMARY_TTL" -gt 60 ]] 2>/dev/null; then
                echo -e "       ${YELLOW}TTL is ${PRIMARY_TTL}s — high TTL means slow failover. Should be ≤ 60${NC}"
            fi
        fi

        # Check SECONDARY record
        SECONDARY_RECORD=$(echo "$APP_RECORDS" | python3 -c "
import sys, json
records = json.load(sys.stdin)
secondary = [r for r in records if r.get('Failover') == 'SECONDARY']
print(json.dumps(secondary[0]) if secondary else '{}')
" 2>/dev/null)

        [[ "$SECONDARY_RECORD" != "{}" ]]
        check "Secondary record has failover_routing_policy type = SECONDARY" "$?"

        if [[ "$SECONDARY_RECORD" != "{}" ]]; then
            # Secondary set_identifier
            SECONDARY_ID=$(echo "$SECONDARY_RECORD" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('SetIdentifier',''))" 2>/dev/null)
            [[ -n "$SECONDARY_ID" ]]
            check "Secondary record has set_identifier set" "$?"

            # Secondary set_identifier is different from primary
            [[ "$SECONDARY_ID" != "$PRIMARY_ID" ]]
            check "Primary and secondary set_identifiers are different" "$?"

            # Secondary TTL
            SECONDARY_TTL=$(echo "$SECONDARY_RECORD" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('TTL','9999'))" 2>/dev/null)
            [[ "$SECONDARY_TTL" -le 60 ]] 2>/dev/null
            check "Secondary record TTL is 60 seconds or less (was: ${SECONDARY_TTL}s)" "$?"
            if [[ "$SECONDARY_TTL" -gt 60 ]] 2>/dev/null; then
                echo -e "       ${YELLOW}TTL is ${SECONDARY_TTL}s — this was the 3600s bug. Should be ≤ 60${NC}"
            fi

            # Secondary should NOT have a health check (last resort — serves unconditionally)
            SECONDARY_HC=$(echo "$SECONDARY_RECORD" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('HealthCheckId',''))" 2>/dev/null)
            [[ -z "$SECONDARY_HC" ]]
            check "Secondary record has no health check (correct — it is the last resort)" "$?"
        fi
    fi
else
    warn "Skipping DNS record AWS validation — zone_id output missing"
fi

# =============================================================================
# SECTION 5: Cross-check health check ID matches between record and resource
# =============================================================================
echo ""
echo -e "${WHITE}── Section 5: Health Check Linkage ──────────────────────────────${NC}"

if [[ -z "$HEALTH_CHECK_ID_MISSING" && -z "$ZONE_ID_MISSING" && "$PRIMARY_RECORD" != "{}" ]]; then
    PRIMARY_HC_ID=$(echo "$PRIMARY_RECORD" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('HealthCheckId',''))" 2>/dev/null)
    [[ "$PRIMARY_HC_ID" == "$HEALTH_CHECK_ID" ]]
    check "Primary record's health_check_id matches the deployed health check resource" "$?"
    if [[ "$PRIMARY_HC_ID" != "$HEALTH_CHECK_ID" ]]; then
        echo -e "       ${YELLOW}Record links to: $PRIMARY_HC_ID${NC}"
        echo -e "       ${YELLOW}Health check is: $HEALTH_CHECK_ID${NC}"
    fi
else
    warn "Skipping health check linkage check — prerequisite outputs missing"
fi

# =============================================================================
# Results summary
# =============================================================================
echo ""
echo -e "${WHITE}────────────────────────────────────────────────────────────────${NC}"
echo -e "  Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, ${YELLOW}$WARN warnings${NC}"
echo -e "${WHITE}────────────────────────────────────────────────────────────────${NC}"
echo ""

if [[ "$FAIL" -eq 0 && "$WARN" -eq 0 ]]; then
    echo -e "${GREEN}  ✅  All checks passed. Route 53 failover is correctly configured.${NC}"
    echo -e "${GREEN}     Don't forget: terraform destroy -auto-approve${NC}"
elif [[ "$FAIL" -eq 0 && "$WARN" -gt 0 ]]; then
    echo -e "${YELLOW}  ⚠️   Checks passed but warnings need attention.${NC}"
    echo -e "${YELLOW}     Review the warnings above before considering this lab complete.${NC}"
else
    echo -e "${RED}  ❌  $FAIL check(s) failed. Review the errors above.${NC}"
    echo -e "${RED}     Fix the issues in main.tf, then run: terraform apply -auto-approve${NC}"
fi

echo ""
[[ "$FAIL" -eq 0 ]]
