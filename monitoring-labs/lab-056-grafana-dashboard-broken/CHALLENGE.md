Title: Empty Dashboards — Grafana Data Source and Panel Debugging
Difficulty: ⭐⭐ (Intermediate)
Time: 15-20 minutes
Category: Monitoring / Grafana
Skills: Grafana datasources, Prometheus queries, PromQL, dashboard JSON, panel configuration

## Scenario

Grafana is running and dashboards are provisioned, but all panels show "No data". The Prometheus data source is configured but the connection isn't working, and the PromQL queries in the dashboard panels have errors.

> **INCIDENT-MON-007**: Grafana dashboards deployed but showing "No data" on all panels. Prometheus is collecting metrics fine but Grafana can't query them. Data source or query configuration issue.

## Objectives

1. Start the environment with `docker compose up -d`
2. Access Grafana at http://localhost:3000 (admin/admin)
3. Fix the Prometheus data source configuration
4. Fix the PromQL queries in the dashboard panels
5. Verify all panels show data

## What You're Practising

Grafana is the standard dashboarding tool paired with Prometheus. Setting up data sources, writing PromQL queries, and debugging empty panels are everyday cloud engineering tasks.
