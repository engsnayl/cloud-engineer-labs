# Solution Walkthrough — Grafana Dashboard Broken

## The Problem

Grafana is running but the application dashboard shows no data in any panel. The dashboard has multiple configuration errors. There are **five bugs**:

1. **Wrong data source URL** — the Prometheus data source points to `http://localhost:9090`, but inside the Docker network, Grafana needs to reach Prometheus at `http://prometheus:9090` (using the Docker Compose service name).
2. **`rates()` instead of `rate()`** — the Request Rate panel uses `rates(http_requests_total[5m])`, but `rates` is not a PromQL function. The correct function is `rate()`.
3. **Single quotes in label matcher** — the Error Rate panel uses `status='500'`, but PromQL requires double quotes for label matchers: `status="500"`.
4. **Wrong histogram_quantile argument** — the P95 Duration panel passes `95` to `histogram_quantile()`, but this function takes a value between 0 and 1. The correct argument is `0.95`.
5. **Wrong metric name** — the Active Connections panel queries `active_connection` (singular), but the metric is named `active_connections` (plural).

## Thought Process

When Grafana panels show "No data," an experienced engineer checks:

1. **Data source connectivity** — can Grafana reach Prometheus? Test with the "Save & Test" button in data source settings. `localhost` from inside a container refers to the container itself, not the host or other containers.
2. **PromQL syntax** — are the queries valid? Paste them into the Prometheus expression browser (`/graph`) to test independently from Grafana.
3. **Metric names** — do the queried metrics actually exist? Check `http://prometheus:9090/api/v1/label/__name__/values` for available metric names.
4. **Function arguments** — `histogram_quantile` expects 0-1, not 0-100. `rate` expects a range vector `[5m]`, not an instant vector.

## Step-by-Step Solution

### Step 1: Fix Bug 1 — Correct the data source URL

Open `provisioning/datasources/prometheus.yml` and change the URL.

```yaml
# BROKEN
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://localhost:9090     # Wrong — localhost means Grafana itself!
    isDefault: true

# FIXED
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090    # Docker Compose service name
    isDefault: true
```

**What this does:** Inside a Docker network, each container has its own `localhost`. When Grafana tries to reach `http://localhost:9090`, it's trying to connect to port 9090 on itself — which has nothing running there. Changing to `http://prometheus:9090` uses Docker's internal DNS to resolve `prometheus` to the Prometheus container's IP address. This is the most fundamental networking concept in Docker Compose.

### Step 2: Fix Bug 2 — Change `rates()` to `rate()`

Open `provisioning/dashboards/app-dashboard.json` and find the Request Rate panel.

```json
// BROKEN
{
  "title": "Request Rate",
  "targets": [
    {
      "expr": "rates(http_requests_total[5m])"
    }
  ]
}

// FIXED
{
  "title": "Request Rate",
  "targets": [
    {
      "expr": "rate(http_requests_total[5m])"
    }
  ]
}
```

**What this does:** `rates` is not a PromQL function — it doesn't exist. The correct function is `rate()`, which calculates the per-second average rate of increase of a counter over a time window. `rate(http_requests_total[5m])` means "how many requests per second, averaged over the last 5 minutes." This is the most commonly used PromQL function for dashboards.

### Step 3: Fix Bug 3 — Use double quotes in label matchers

Find the Error Rate panel and fix the label matcher quotes.

```json
// BROKEN
{
  "title": "Error Rate (%)",
  "targets": [
    {
      "expr": "sum(rate(http_requests_total{status='500'}[5m])) / sum(rate(http_requests_total[5m])) * 100"
    }
  ]
}

// FIXED
{
  "title": "Error Rate (%)",
  "targets": [
    {
      "expr": "sum(rate(http_requests_total{status=\"500\"}[5m])) / sum(rate(http_requests_total[5m])) * 100"
    }
  ]
}
```

**What this does:** PromQL uses double quotes for label matchers, not single quotes. `status='500'` is a syntax error. `status="500"` correctly filters for time series where the `status` label equals "500". Note that in JSON, the double quotes inside the expression must be escaped with backslashes (`\"`).

### Step 4: Fix Bug 4 — Use 0.95 instead of 95 for histogram_quantile

Find the Request Duration panel and fix the quantile argument.

```json
// BROKEN
{
  "title": "Request Duration (p95)",
  "targets": [
    {
      "expr": "histogram_quantile(95, rate(http_request_duration_seconds_bucket[5m]))"
    }
  ]
}

// FIXED
{
  "title": "Request Duration (p95)",
  "targets": [
    {
      "expr": "histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))"
    }
  ]
}
```

**What this does:** `histogram_quantile()` expects the quantile as a fraction between 0 and 1, not a percentage. `0.95` means the 95th percentile (p95). Passing `95` tells Prometheus to compute the 9500th percentile, which returns infinity or nonsensical values. This is a very common PromQL mistake.

### Step 5: Fix Bug 5 — Correct the metric name to plural

Find the Active Connections panel and fix the metric name.

```json
// BROKEN
{
  "title": "Active Connections",
  "targets": [
    {
      "expr": "active_connection"
    }
  ]
}

// FIXED
{
  "title": "Active Connections",
  "targets": [
    {
      "expr": "active_connections"
    }
  ]
}
```

**What this does:** The application code defines the metric as `active_connections` (plural) using `Gauge('active_connections', ...)`. Querying `active_connection` (singular) returns no results because that metric doesn't exist. Prometheus metric names are exact-match — there's no fuzzy matching. Always verify metric names exist before using them in queries.

### Step 6: Restart Grafana and validate

```bash
# Restart Grafana to load the updated provisioning files
docker compose restart grafana

# Wait for Grafana to start
sleep 10

# Check Grafana is healthy
curl -s http://localhost:3000/api/health

# Verify data source
grep "prometheus:9090" provisioning/datasources/prometheus.yml

# Verify PromQL fixes
grep -c "rate(" provisioning/dashboards/app-dashboard.json    # Should find rate(, not rates(
grep "0.95" provisioning/dashboards/app-dashboard.json         # Should find 0.95
grep "active_connections" provisioning/dashboards/app-dashboard.json  # Plural
```

## Docker Lab vs Real Life

- **Grafana Terraform provider:** In production, dashboards are managed as code using the Grafana Terraform provider or the Grafana API. Changes are version-controlled and deployed through CI/CD.
- **Dashboard variables:** Production dashboards use template variables (dropdowns) to filter by environment, service, or instance. One dashboard serves all environments instead of duplicating dashboards.
- **Annotations:** Production dashboards overlay deployment markers, incident timelines, and configuration changes on graphs. This correlates metric changes with events.
- **Alert rules in Grafana:** Modern Grafana (8+) supports native alerting. PromQL alerts can be defined directly in Grafana alongside dashboard panels.
- **Dashboard-as-code:** Tools like Grafonnet (Jsonnet library) or Grafana's provisioning system generate dashboards programmatically. Hand-editing JSON is error-prone — as this lab demonstrates.

## Key Concepts Learned

- **Docker networking: use service names, not localhost** — inside a Docker network, `localhost` refers to the container itself. Use the Docker Compose service name (`prometheus`) to reach other containers.
- **`rate()` not `rates()`** — PromQL's function for calculating per-second rates of counters is `rate()`. There is no `rates()` function.
- **PromQL uses double quotes for label matchers** — `{status="500"}` is correct. `{status='500'}` is a syntax error. This differs from some other query languages.
- **`histogram_quantile` takes 0-1, not percentages** — 0.95 = p95, 0.99 = p99, 0.5 = p50 (median). Passing 95 gives nonsensical results.
- **Metric names must match exactly** — `active_connection` vs `active_connections`. Check available metrics in Prometheus before writing queries.

## Common Mistakes

- **`localhost` in Docker data source URLs** — this is the #1 Grafana-in-Docker issue. Always use the Docker Compose service name.
- **PromQL typos that return empty results** — PromQL doesn't error on non-existent metric names. It just returns empty. Always check that your metric names exist.
- **Percentage vs fraction confusion** — `histogram_quantile(95, ...)` returns infinity. `histogram_quantile(0.95, ...)` returns the actual p95 value. This mistake is silent — the query runs but returns meaningless data.
- **Not escaping quotes in JSON** — PromQL needs double quotes, but JSON also uses double quotes for strings. Inside JSON, PromQL double quotes must be escaped: `\"500\"`.
- **Editing provisioned dashboards in the UI** — changes to provisioned dashboards in Grafana's UI are lost on restart. Always edit the source JSON files and re-provision.
