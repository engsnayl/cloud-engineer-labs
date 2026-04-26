Title: Empty Dashboards — Grafana Data Source and Panel Debugging
Difficulty: ⭐⭐ (Intermediate)
Time: 15-20 minutes
Category: Monitoring / Grafana
Skills: Grafana datasources, Prometheus queries, PromQL, dashboard JSON, panel configuration

## Scenario

You are on the on-call rota. The following ticket has just been assigned to you. The author of the dashboard is on holiday for the next week.

> **INCIDENT-MON-007** — *Priority: P3*
>
> The new "Application Dashboard" deployment finished overnight. Grafana is up and the dashboard is provisioned, but every panel is showing "No data". Prometheus appears to be collecting metrics fine — the SRE team confirmed the app is exposing `/metrics` and Prometheus is scraping it.
>
> Something between Prometheus and Grafana — or in the dashboard itself — is broken. Please investigate and resolve. The dashboard needs to be functional before the product review on Friday.
>
> **Stack:** Grafana, Prometheus, and the application all run in Docker Compose. Source files for the Grafana provisioning live in `provisioning/datasources/` and `provisioning/dashboards/`.

## Your Job

Bring the dashboard back to a working state where every panel renders meaningful data. You have full access to the source files, the running containers, and both the Grafana and Prometheus web UIs.

You're not given a list of what's wrong. Diagnose it.

## Validation

Run `lab validate monitoring/lab-056-grafana-dashboard-broken` once you believe the dashboard is healthy.

## What You're Practising

Grafana paired with Prometheus is the de-facto open-source observability stack. Diagnosing empty panels — distinguishing data source problems from query problems from metric problems — is a daily task for any team running this stack. The diagnostic pathway here (eliminate possibilities by testing each layer in isolation) is the same pathway you'll use for every Grafana incident you ever pick up.
