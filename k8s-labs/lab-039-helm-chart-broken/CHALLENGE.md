Title: Helm Chart Won't Install — Debug a Broken Chart
Difficulty: ⭐⭐⭐ (Advanced)
Time: 20-25 minutes
Category: Kubernetes / Helm
Skills: helm install, helm template, Chart.yaml, values.yaml, Go templates, release debugging

## Scenario

The team's Helm chart for the web application won't install. `helm install` fails with template errors, and even when forced, the resulting resources don't work correctly.

> **INCIDENT-K8S-011**: `helm install webapp ./webapp-chart` failing with multiple template errors. Chart was recently refactored and hasn't been tested. Deployment blocked.

## Objectives

1. Fix `Chart.yaml` — it must have a `name` field and use `apiVersion: v2`
2. Fix `values.yaml` — `appLabel` must not contain spaces, and the service port must be a number (not a quoted string)
3. Fix template syntax errors in the deployment and service templates
4. `helm template webapp ./webapp-chart` must render without errors
5. If a cluster is available, install the chart and verify pods are running

## How to Use This Lab

1. Examine the chart structure in `webapp-chart/`
2. Run `helm template webapp ./webapp-chart` to see errors
3. Fix each error, re-run template to verify
4. When clean: `helm install webapp ./webapp-chart`
5. Run validate.sh to check

**Requires:** Helm 3 installed, Kubernetes cluster (kind/minikube/KodeKloud)

## What You're Practising

Helm is the standard package manager for Kubernetes. Almost every production K8s deployment uses Helm charts. Debugging chart issues is a daily task for cloud engineers.
