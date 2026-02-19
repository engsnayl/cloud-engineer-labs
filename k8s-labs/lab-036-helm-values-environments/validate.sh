#!/bin/bash
PASS=0
FAIL=0
check() {
    local description="$1"; local result="$2"
    if [[ "$result" == "0" ]]; then echo -e "  ✅  $description"; ((PASS++))
    else echo -e "  ❌  $description"; ((FAIL++)); fi
}
echo "Running validation checks..."
echo ""

# Production checks
prod=$(helm template webapp ./api-chart -f values-production.yaml 2>/dev/null)

echo "$prod" | grep -q "replicas: [3-9]\|replicas: [1-9][0-9]"
check "Production has 3+ replicas" "$?"

echo "$prod" | grep -q "production-db\|prod-db\|prod.*db"
check "Production points to production database" "$?"

echo "$prod" | grep -qi "LOG_LEVEL.*info\|LOG_LEVEL.*warn"
check "Production log level is info or warn (not debug)" "$?"

echo "$prod" | grep -q "CACHE_ENABLED.*true"
check "Production cache is enabled" "$?"

echo "$prod" | grep -q "HorizontalPodAutoscaler"
check "Production has HPA enabled" "$?"

# Staging checks
stg=$(helm template webapp ./api-chart -f values-staging.yaml 2>/dev/null)

echo "$stg" | grep -q "replicas: 1"
check "Staging has 1 replica" "$?"

echo "$stg" | grep -q "staging-db"
check "Staging points to staging database" "$?"

echo "$stg" | grep -q "LOG_LEVEL.*debug"
check "Staging log level is debug" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
