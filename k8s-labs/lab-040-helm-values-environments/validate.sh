#!/bin/bash
# =============================================================================
# Validation Criteria (from CHALLENGE.md):
#   - values-production.yaml has 3+ replicas, production DB, info logging
#   - `helm template -f values-production.yaml` shows production DB, info logging, HPA
#   - `helm template -f values-staging.yaml` shows 1 replica, staging DB, debug logging
#   - ConfigMap renders correct environment variables
#   - Resource limits are appropriate per environment
#
# NOTE: replicaCount is checked directly from the values file, not from the rendered
# template. When autoscaling is enabled, the Deployment template intentionally omits
# the replicas field (the HPA owns it), so grepping rendered output would always fail.
# =============================================================================
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

# Check replicaCount directly from values file (not rendered template)
# When autoscaling is enabled, the Deployment omits replicas — the HPA owns it
grep -qE "replicaCount: ([3-9]|[1-9][0-9])" values-production.yaml
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
