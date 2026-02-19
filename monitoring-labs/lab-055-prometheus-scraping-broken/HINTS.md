# Hints — Monitoring Lab 055: Prometheus Scraping

## Hint 1 — Check the targets page
Visit http://localhost:9090/targets (or `curl http://localhost:9090/api/v1/targets`). Which targets are DOWN and why?

## Hint 2 — Fix the obvious issues
- Scrape interval: 600s = 10 minutes. Use 15s or 30s.
- App port: apps expose metrics on 8080, not 9090
- Metrics path: apps use `/metrics`, not `/api/metrics`
- Hostname: Docker Compose service is `node-exporter` (with hyphen), not `node_exporter` (with underscore)

## Hint 3 — After fixing prometheus.yml
Restart Prometheus: `docker compose restart prometheus`. Then wait 15-30 seconds and check targets again.
