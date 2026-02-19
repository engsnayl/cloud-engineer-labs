# Hints — Monitoring Lab 056: Grafana Dashboard

## Hint 1 — Data source first
In `provisioning/datasources/prometheus.yml`, the URL is `http://localhost:9090`. Inside Docker, Grafana can't reach Prometheus via localhost — use `http://prometheus:9090` (the Docker Compose service name).

## Hint 2 — PromQL function names
- `rates()` doesn't exist — it's `rate()`
- Label matchers use double quotes: `{status="500"}` not `{status='500'}`

## Hint 3 — PromQL values
- `histogram_quantile()` takes a value between 0 and 1. For p95, use `0.95` not `95`
- Check metric names exactly: `active_connections` not `active_connection`

## Hint 4 — After fixing
Restart Grafana: `docker compose restart grafana`. Wait 30 seconds, then check the dashboard.
