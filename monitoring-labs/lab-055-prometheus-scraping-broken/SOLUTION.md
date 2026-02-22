# Solution Walkthrough — Prometheus Scraping Broken

## The Problem

Prometheus is running but no metrics are being collected. The targets page shows all endpoints as DOWN. Grafana dashboards are empty because there's no data. The `prometheus.yml` configuration has **four bugs**:

1. **Scrape interval too long** — `scrape_interval: 600s` means Prometheus only collects metrics every 10 minutes. Dashboards appear empty because data points are too sparse, and short-lived issues are completely missed.
2. **Wrong port for app targets** — the app targets use port `9090` (Prometheus's own port) instead of `8080` where the applications actually expose their `/metrics` endpoint.
3. **Wrong metrics path** — `metrics_path: '/api/metrics'` but the applications expose metrics at `/metrics` (the default). Prometheus gets 404 errors on every scrape attempt.
4. **Wrong hostname for node exporter** — the target uses `node_exporter` (with underscore) but the Docker Compose service is named `node-exporter` (with hyphen). DNS resolution fails.

## Thought Process

When Prometheus targets show as DOWN, an experienced engineer checks:

1. **Can Prometheus reach the targets?** — check the targets page (`/targets`) for error messages. "Connection refused" means wrong host/port. "404" means wrong path.
2. **Are the ports correct?** — Prometheus default is 9090. Applications often use 8080 or custom ports. Node exporter uses 9100. Each target needs the correct port.
3. **Is the metrics path correct?** — the default is `/metrics`. If the application uses a custom path, it must be explicitly configured.
4. **Do hostnames resolve?** — in Docker Compose, service names are hostnames. Underscores vs hyphens matter for DNS resolution.

## Step-by-Step Solution

### Step 1: Fix Bug 1 — Set a reasonable scrape interval

```yaml
# BROKEN
global:
  scrape_interval: 600s      # 10 minutes — way too long!
  evaluation_interval: 600s

# FIXED
global:
  scrape_interval: 15s        # Every 15 seconds — standard default
  evaluation_interval: 15s
```

**What this does:** Changes the scrape interval from 10 minutes to 15 seconds. Prometheus scrapes each target at this interval to collect new metric values. 15 seconds is the standard default — it provides enough resolution for dashboards and alerting without overwhelming the targets. With 600s, dashboards have one data point every 10 minutes, making them nearly useless for real-time monitoring.

### Step 2: Fix Bug 2 — Correct the app target ports

```yaml
# BROKEN
  - job_name: 'app'
    static_configs:
      - targets: ['app1:9090', 'app2:9090']    # Wrong port!

# FIXED
  - job_name: 'app'
    static_configs:
      - targets: ['app1:8080', 'app2:8080']    # Correct port
```

**What this does:** Changes the port from 9090 (Prometheus's own port) to 8080 (where the applications actually serve metrics). Port 9090 is where Prometheus listens, not where the applications listen. Scraping an application on port 9090 results in "Connection refused" because nothing in the application is listening there.

### Step 3: Fix Bug 3 — Correct the metrics path

```yaml
# BROKEN
  - job_name: 'app'
    metrics_path: '/api/metrics'    # Wrong path!
    static_configs:
      - targets: ['app1:8080', 'app2:8080']

# FIXED
  - job_name: 'app'
    metrics_path: '/metrics'        # Correct path (or remove — /metrics is the default)
    static_configs:
      - targets: ['app1:8080', 'app2:8080']
```

**What this does:** Changes the metrics endpoint from `/api/metrics` to `/metrics`. The Prometheus client libraries (in Python, Go, Java, etc.) expose metrics at `/metrics` by default. When Prometheus scrapes `/api/metrics`, it gets a 404 response and marks the target as DOWN. You could also remove the `metrics_path` line entirely since `/metrics` is the default.

### Step 4: Fix Bug 4 — Correct the node exporter hostname

```yaml
# BROKEN
  - job_name: 'node'
    static_configs:
      - targets: ['node_exporter:9100']    # Underscore — wrong!

# FIXED
  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']    # Hyphen — matches Docker Compose service name
```

**What this does:** Changes `node_exporter` (underscore) to `node-exporter` (hyphen) to match the Docker Compose service name. In Docker Compose, service names become DNS hostnames. Docker's built-in DNS resolves `node-exporter` to the container's IP address. `node_exporter` doesn't resolve to anything, causing "name resolution failed" errors.

### Step 5: The complete fixed prometheus.yml

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'app'
    metrics_path: '/metrics'
    static_configs:
      - targets: ['app1:8080', 'app2:8080']

  - job_name: 'node'
    static_configs:
      - targets: ['node-exporter:9100']
```

### Step 6: Restart Prometheus and validate

```bash
# Restart Prometheus to pick up the new config
docker compose restart prometheus

# Wait for scraping to begin
sleep 30

# Check targets are UP
curl -s http://localhost:9090/api/v1/targets | python3 -c "
import sys, json
data = json.load(sys.stdin)
for target in data['data']['activeTargets']:
    print(f\"{target['labels']['job']}: {target['health']}\")
"

# Check that metrics are being collected
curl -s 'http://localhost:9090/api/v1/query?query=up' | python3 -c "
import sys, json
data = json.load(sys.stdin)
for result in data['data']['result']:
    print(f\"{result['metric']['job']}: up={result['value'][1]}\")
"
```

## Docker Lab vs Real Life

- **Service discovery:** Production Prometheus uses service discovery (Kubernetes SD, EC2 SD, Consul SD) instead of static targets. New pods or instances are automatically discovered and scraped.
- **Relabeling:** `relabel_configs` in Prometheus lets you transform labels, filter targets, and customize scrape behavior per target. This is essential for managing large deployments.
- **Federation:** Large organizations run multiple Prometheus servers and use federation or Thanos/Cortex to aggregate metrics across clusters and regions.
- **Recording rules:** Production Prometheus uses recording rules to pre-compute expensive queries. Instead of calculating `rate(http_requests_total[5m])` on every dashboard load, a recording rule stores the result as a new metric.
- **Remote write:** Prometheus can write metrics to long-term storage (Thanos, Cortex, Mimir, Grafana Cloud) for retention beyond the local disk capacity.

## Key Concepts Learned

- **Scrape interval of 15s is the standard default** — 600s (10 minutes) is far too long for useful monitoring. 15-30 seconds gives good resolution for dashboards and alerting.
- **Each target needs the correct port** — Prometheus (9090), node exporter (9100), and your application (often 8080) all use different ports. Don't mix them up.
- **`/metrics` is the default path** — unless your application uses a custom path, you don't need to set `metrics_path`. If you do set it, make sure it matches what the application actually serves.
- **Docker Compose service names are DNS hostnames** — hyphens and underscores are different characters. The hostname must exactly match the service name in `docker-compose.yml`.
- **Check the `/targets` page first** — Prometheus tells you exactly why each target is down. "Connection refused," "404," or "name resolution failed" each point to a specific configuration error.

## Common Mistakes

- **Confusing Prometheus port with target ports** — 9090 is Prometheus, not your application. This is the #1 scraping misconfiguration.
- **Wrong metrics path** — `/api/metrics`, `/prometheus/metrics`, `/actuator/prometheus` — different frameworks use different paths. Check your application's documentation.
- **Underscores vs hyphens in hostnames** — Docker DNS uses the exact service name. `node_exporter` and `node-exporter` are completely different hostnames.
- **Not restarting after config changes** — editing `prometheus.yml` doesn't take effect until Prometheus is restarted or receives a reload signal (`kill -HUP` or `/-/reload` endpoint).
- **Scrape interval too short** — while 600s is too long, 1s is too short and creates excessive load on both Prometheus and the targets. 15-30s is the sweet spot for most use cases.
