#!/bin/bash
# =============================================================================
# Lab 056 — Grafana Dashboard Broken — Validation
#
# Validation Criteria (from CHALLENGE.md):
#   - Grafana is accessible on port 3000
#   - Prometheus data source resolves to prometheus:9090 and answers queries
#   - Prometheus is scraping the app target successfully
#   - The dashboard is loaded into Grafana (not just on disk)
#   - All four PromQL queries are valid AND return data
# =============================================================================
PASS=0
FAIL=0

check() {
    local description="$1"; local result="$2"
    if [[ "$result" == "0" ]]; then
        echo -e "  ✅  $description"
        ((PASS++))
    else
        echo -e "  ❌  $description"
        ((FAIL++))
    fi
}

echo "Running validation checks..."
echo ""

# -------------------------------------------------------------------
# 1. Source-file checks (cheap pre-flight)
# -------------------------------------------------------------------
echo "── Source files ──"

grep -q "http://prometheus:9090" provisioning/datasources/prometheus.yml 2>/dev/null
check "Datasource URL points to prometheus:9090 (not localhost)" "$?"

dashboard="provisioning/dashboards/app-dashboard.json"

grep -q '"rate(' "$dashboard" 2>/dev/null && ! grep -q '"rates(' "$dashboard" 2>/dev/null
check "Request rate uses 'rate' not 'rates'" "$?"

grep -q 'status=\\"500\\"' "$dashboard" 2>/dev/null || grep -q 'status="500"' "$dashboard" 2>/dev/null
check "Error rate uses double quotes for label matcher" "$?"

! grep -q "histogram_quantile(95," "$dashboard" 2>/dev/null && grep -q "histogram_quantile(0.95," "$dashboard" 2>/dev/null
check "Histogram quantile uses 0.95 (not 95)" "$?"

grep -q "active_connections" "$dashboard" 2>/dev/null && ! grep -qE '"expr":\s*"active_connection"' "$dashboard" 2>/dev/null
check "Active connections metric name is correct (plural)" "$?"

# -------------------------------------------------------------------
# 2. Service health checks (services are actually running)
# -------------------------------------------------------------------
echo ""
echo "── Service health ──"

curl -sf http://localhost:3000/api/health >/dev/null 2>&1
check "Grafana is healthy (port 3000 responding)" "$?"

curl -sf http://localhost:9090/-/healthy >/dev/null 2>&1
check "Prometheus is healthy (port 9090 responding)" "$?"

# Prometheus is scraping the app target successfully
target_health=$(curl -s "http://localhost:9090/api/v1/targets" 2>/dev/null \
  | grep -o '"job":"app","[^}]*"health":"[^"]*"' \
  | grep -o '"health":"[^"]*"' \
  | head -1 \
  | sed 's/.*"health":"//;s/"//')
[[ "$target_health" == "up" ]]
check "Prometheus app target is up (scraping /metrics successfully)" "$?"

# -------------------------------------------------------------------
# 3. End-to-end checks (Grafana ↔ Prometheus actually talking)
# -------------------------------------------------------------------
echo ""
echo "── End-to-end ──"

# The Grafana datasource health probe — this is the same call the "Save & Test"
# button makes in the UI. Catches typos that pass the grep but fail in reality.
ds_status=$(curl -s -u admin:admin "http://localhost:3000/api/datasources/name/Prometheus/health" 2>/dev/null \
  | grep -o '"status":"[^"]*"' \
  | head -1 \
  | sed 's/.*"status":"//;s/"//')
[[ "$ds_status" == "OK" ]]
check "Grafana datasource health probe returns OK" "$?"

# Dashboard is actually loaded into Grafana (not just sat on disk as a file)
curl -sf -u admin:admin "http://localhost:3000/api/search?query=Application%20Dashboard" 2>/dev/null \
  | grep -q '"title":"Application Dashboard"'
check "Application Dashboard is loaded into Grafana" "$?"

# -------------------------------------------------------------------
# 4. Query checks (each fixed query actually returns a result)
# -------------------------------------------------------------------
echo ""
echo "── Queries return data ──"

query_returns_data() {
    # Returns 0 (success) if the PromQL query returns at least one result
    local query="$1"
    local result_count
    result_count=$(curl -s --get \
        --data-urlencode "query=${query}" \
        "http://localhost:9090/api/v1/query" 2>/dev/null \
      | grep -o '"value":\[' \
      | wc -l)
    [[ "$result_count" -ge 1 ]]
}

query_returns_data "rate(http_requests_total[5m])"
check "Request rate query returns data" "$?"

query_returns_data 'sum(rate(http_requests_total{status="500"}[5m])) / sum(rate(http_requests_total[5m])) * 100'
check "Error rate query returns data" "$?"

query_returns_data "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))"
check "P95 duration query returns data" "$?"

query_returns_data "active_connections"
check "Active connections query returns data" "$?"

# -------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
