Title: Wrong Config in Production — Helm Values and Overrides
Difficulty: ⭐⭐⭐ (Advanced)
Time: 20-25 minutes
Category: Kubernetes / Helm
Skills: values.yaml, value overrides, helm install -f, helm upgrade, configmaps from Helm, environment separation

## Scenario

The same Helm chart deploys to staging and production, but production is running with staging values — wrong replica count, wrong resource limits, wrong database connection, and debug logging enabled in prod.

> **INCIDENT-K8S-012**: Production running with 1 replica instead of 4. Debug logging flooding CloudWatch. Database pointing at staging RDS. Helm values override not applied correctly.

## Objectives

1. Review the base values.yaml and environment-specific overrides
2. Fix the production values file (values-production.yaml)
3. Fix the staging values file (values-staging.yaml)
4. Ensure the chart templates correctly reference all values
5. Verify each environment gets the right configuration

## How to Use This Lab

1. Run `helm template webapp ./api-chart` to see defaults
2. Run `helm template webapp ./api-chart -f values-production.yaml` to see prod config
3. Compare and fix the values files
4. Run validate.sh to check

**Requires:** Helm 3 installed

## What You're Practising

Managing environment-specific configuration with Helm values overrides is how every team handles staging vs production differences. Getting this wrong is one of the most common causes of production incidents.
