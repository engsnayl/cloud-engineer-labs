Title: Empty Dashboards — Grafana Data Source and Panel Debugging
Difficulty: ⭐⭐ (Intermediate)
Time: 20-30 minutes
Category: Monitoring / Grafana
Skills: Grafana datasources, Grafana provisioning, Prometheus queries, PromQL, dashboard JSON, panel configuration, log reading

## Scenario

You are on the on-call rota. The following ticket has just been assigned to you. The author of the dashboard is on holiday for the next week.

> **INCIDENT-MON-007** — *Priority: P3*
>
> The new "Application Dashboard" deployment finished overnight. Grafana is up and the dashboard is meant to be provisioned, but the product team is reporting that nothing's appearing on the screen as expected. Prometheus appears to be collecting metrics fine — the SRE team confirmed the app is exposing `/metrics` and Prometheus is scraping it.
>
> Something between Prometheus and Grafana — or in the dashboard itself — is broken. Please investigate and resolve. The dashboard needs to be functional before the product review on Friday.
>
> **Stack:** Grafana, Prometheus, and the application all run in Docker Compose. Source files for the Grafana provisioning live in `provisioning/datasources/` and `provisioning/dashboards/`.

## Your Job

Bring the dashboard back to a working state where every panel renders meaningful data. You have full access to the source files, the running containers, and both the Grafana and Prometheus web UIs.

You're not given a list of what's wrong. Diagnose it.

## Validation

Run `lab validate monitoring-labs/lab-056-grafana-dashboard-broken` once you believe the dashboard is healthy.

## What You're Practising

Grafana paired with Prometheus is the de-facto open-source observability stack. Diagnosing a broken dashboard — distinguishing provisioning problems from data source problems from query problems from missing-data problems — is a daily task for any team running this stack. The diagnostic pathway here (eliminate possibilities by testing each layer in isolation) is the same pathway you'll use for every Grafana incident you ever pick up.
