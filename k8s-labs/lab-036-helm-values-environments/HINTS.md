# Hints — K8s Lab 036: Helm Values & Environments

## Hint 1 — Compare the environments
Run `helm template webapp ./api-chart -f values-production.yaml` and check: replica count, database host, log level, cache, autoscaling. Each should differ from staging.

## Hint 2 — Production values should be
- replicaCount: 4 (or 3+)
- logLevel: info (or warn)
- databaseHost: production-db.internal (or similar)
- databaseName: api_production
- cacheEnabled: true
- maxConnections: 50+
- autoscaling.enabled: true with minReplicas: 2, maxReplicas: 10

## Hint 3 — Resources
Production needs more resources: cpu limits 1000m+, memory 1Gi+. Staging can stay small.
