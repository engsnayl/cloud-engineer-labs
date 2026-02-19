Title: Helm Chart Won't Install — Debug a Broken Chart
Difficulty: ⭐⭐⭐ (Advanced)
Time: 20-25 minutes
Category: Kubernetes / Helm
Skills: helm install, helm template, Chart.yaml, values.yaml, Go templates, release debugging

## Scenario

The team's Helm chart for the web application won't install. `helm install` fails with template errors, and even when forced, the resulting resources don't work correctly.

> **INCIDENT-K8S-011**: `helm install webapp ./webapp-chart` failing with multiple template errors. Chart was recently refactored and hasn't been tested. Deployment blocked.

## Objectives

1. Run `helm template` or `helm install --dry-run` to identify errors
2. Fix the Chart.yaml metadata
3. Fix template syntax errors in the deployment and service templates
4. Fix the values.yaml defaults
5. Successfully install the chart and verify the app runs

## Validation Criteria

- `helm template webapp ./webapp-chart` renders without errors
- Chart installs successfully with `helm install`
- Deployment creates running pods
- Service exposes the application correctly

## How to Use This Lab

1. Examine the chart structure in `webapp-chart/`
2. Run `helm template webapp ./webapp-chart` to see errors
3. Fix each error, re-run template to verify
4. When clean: `helm install webapp ./webapp-chart`
5. Run validate.sh to check

**Requires:** Helm 3 installed, Kubernetes cluster (kind/minikube/KodeKloud)

## What You're Practising

Helm is the standard package manager for Kubernetes. Almost every production K8s deployment uses Helm charts. Debugging chart issues is a daily task for cloud engineers.
