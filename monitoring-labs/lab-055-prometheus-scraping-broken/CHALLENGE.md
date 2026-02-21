Title: No Metrics — Prometheus Scraping Broken
Difficulty: ⭐⭐ (Intermediate)
Time: 15-20 minutes
Category: Monitoring / Prometheus
Skills: prometheus.yml, scrape configs, targets, metrics endpoints, service discovery

## Scenario

Prometheus is running but no metrics are being collected. The targets page shows all endpoints as DOWN. The Prometheus configuration has several issues preventing scraping.

> **INCIDENT-MON-006**: Grafana dashboards all empty. Prometheus targets page shows 0/3 targets UP. No metrics data for the last 2 hours. Alerting is blind.

## Objectives

1. Get Prometheus running and healthy
2. Fix the `prometheus.yml` configuration — scrape interval must be reasonable (10s-60s)
3. Ensure the metrics path is correct (`/metrics`)
4. All three targets must be showing as UP in Prometheus
5. Verify metrics are being collected (e.g. the `up` metric returns data)

## What You're Practising

Prometheus is the standard metrics collection system in cloud-native environments. Configuring scrape targets, understanding service discovery, and debugging collection issues are daily tasks for cloud engineers.
