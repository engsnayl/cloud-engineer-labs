Title: No Metrics — Prometheus Scraping Broken
Difficulty: ⭐⭐ (Intermediate)
Time: 15-20 minutes
Category: Monitoring / Prometheus
Skills: prometheus.yml, scrape configs, targets, metrics endpoints, service discovery

## Scenario

Prometheus is running but no metrics are being collected. The targets page shows all endpoints as DOWN. The Prometheus configuration has several issues preventing scraping.

> **INCIDENT-MON-006**: Grafana dashboards all empty. Prometheus targets page shows 0/3 targets UP. No metrics data for the last 2 hours. Alerting is blind.

## Objectives

1. Start the environment with `docker compose up -d`
2. Access Prometheus at http://localhost:9090 (or exec into the container)
3. Check the targets page / configuration
4. Fix the prometheus.yml configuration
5. Verify all three targets are being scraped

## Validation Criteria

- Prometheus is running and accessible
- All three scrape targets are UP
- Metrics are being collected (up metric returns results)
- Configuration passes validation

## What You're Practising

Prometheus is the standard metrics collection system in cloud-native environments. Configuring scrape targets, understanding service discovery, and debugging collection issues are daily tasks for cloud engineers.
