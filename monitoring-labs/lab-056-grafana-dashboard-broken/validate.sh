#!/bin/bash
# =============================================================================
# Lab 056 — Grafana Dashboard Broken — Validation
#
# Validation Criteria (from CHALLENGE.md):
#   - Grafana is accessible on port 3000
#   - Dashboard JSON is in provisioning format (no API-import wrapper)
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

# Dashboard JSON must NOT have the API-import wrapper (Bug 6).
# The provisioning format is a flat object with "title" at the top level.
# The API-import format wraps everything in {"dashboard": {...}}.
python3 -c "
import sys, json
try:
    with open('$dashboard') as f:
        data = json.load(f)
    sys.exit(0 if 'title' in data and 'dashboard' not in data else 1)
except Exception:
    sys.exit(1)
" 2>/dev/null
check "Dashboard JSON is in provisioning format (no outer 'dashboard' wrapper)" "$?"

grep -q '"rate(' "$dashboard" 2>/dev/null && ! grep -q '"rates(' "$dashboard" 2>/dev/null
check "Request rate uses 'rate' not 'rates'" "$?"

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

# Prometheus is scraping the app target successfully — proper JSON parsing
curl -s "http://localhost:9090/api/v1/targets" 2>/dev/null \
  | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    targets = data.get('data', {}).get('activeTargets', [])
    app = next((t for t in targets if t.get('labels', {}).get('job') == 'app'), None)
    sys.exit(0 if app and app.get('health') == 'up' else 1)
except Exception:
    sys.exit(1)
"
check "Prometheus app target is up (scraping /metrics successfully)" "$?"

# -------------------------------------------------------------------
# 3. End-to-end checks (Grafana ↔ Prometheus actually talking)
# -------------------------------------------------------------------
echo ""
echo "── End-to-end ──"

# Get the datasource UID (Grafana 13+ requires UID for health probes)
DS_UID=$(curl -s -u admin:admin http://localhost:3000/api/datasources 2>/dev/null \
  | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    prom = next((d for d in data if d.get('name') == 'Prometheus'), None)
    print(prom['uid'] if prom else '')
except Exception:
    print('')
")

if [[ -n "$DS_UID" ]]; then
    curl -s -u admin:admin "http://localhost:3000/api/datasources/uid/${DS_UID}/health" 2>/dev/null \
      | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    sys.exit(0 if data.get('status') == 'OK' else 1)
except Exception:
    sys.exit(1)
"
    check "Grafana datasource health probe returns OK" "$?"
else
    check "Grafana datasource health probe returns OK" "1"
fi

# Dashboard is actually loaded into Grafana (not just sat on disk as a file)
curl -s -u admin:admin "http://localhost:3000/api/search?query=Application%20Dashboard" 2>/dev/null \
  | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    sys.exit(0 if any(d.get('title') == 'Application Dashboard' for d in data) else 1)
except Exception:
    sys.exit(1)
"
check "Application Dashboard is loaded into Grafana" "$?"

# -------------------------------------------------------------------
# 4. Query checks (each fixed query actually returns a result)
# -------------------------------------------------------------------
echo ""
echo "── Queries return data ──"

query_returns_data() {
    local query="$1"
    curl -s --get \
        --data-urlencode "query=${query}" \
        "http://localhost:9090/api/v1/query" 2>/dev/null \
      | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('status') != 'success':
        sys.exit(1)
    result = data.get('data', {}).get('result', [])
    sys.exit(0 if len(result) > 0 else 1)
except Exception:
    sys.exit(1)
"
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
