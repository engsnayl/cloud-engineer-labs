# Solution Walkthrough — Wrong Config in Production (Helm Values)

## The Problem

The same Helm chart deploys to both staging and production, but **production is running with staging values**. The `values-production.yaml` file was never properly updated — it's essentially a copy of the staging configuration. This means production has:

1. **1 replica instead of 3+** — no redundancy, single point of failure
2. **Debug logging** — flooding logs with verbose output, increasing costs and making real errors hard to find
3. **Staging database connection** — production traffic is hitting the staging database, which means either data corruption or connection failures
4. **Cache disabled** — every request hits the database directly, causing poor performance under load
5. **Undersized resources** — 250m CPU and 256Mi memory are fine for staging but inadequate for production traffic
6. **Autoscaling disabled** — production can't scale under load, leading to outages during traffic spikes
7. **Tiny connection pool** — 10 connections works for staging but will exhaust immediately in production

## Thought Process

When production is running with wrong configuration, an experienced engineer:

1. **Compare rendered output** — run `helm template -f values-production.yaml` and `helm template -f values-staging.yaml` side by side. If they look the same, the values file is wrong.
2. **Check each critical difference** — production should have: more replicas, higher resources, production database, less verbose logging, caching enabled, autoscaling enabled.
3. **Fix the values file, not the templates** — the templates are correct (they reference `.Values.*` properly). The bug is in the data, not the code.
4. **Validate both environments** — after fixing production values, verify that staging values are still correct too.

## Step-by-Step Solution

### Step 1: Render the chart with production values to see the problem

```bash
helm template webapp ./api-chart -f values-production.yaml
```

**What this does:** Shows what Kubernetes resources would be created for production. You'll see 1 replica, staging database host, debug logging — all wrong for production.

### Step 2: Compare with staging

```bash
helm template webapp ./api-chart -f values-staging.yaml
```

**What this does:** Shows staging resources. If production and staging output looks nearly identical, the production values file hasn't been customized.

### Step 3: Fix values-production.yaml

Replace the broken production values with proper production configuration:

```yaml
# Production overrides
replicaCount: 4

config:
  logLevel: info
  databaseHost: production-db.internal
  databasePort: 5432
  databaseName: api_production
  cacheEnabled: true
  maxConnections: 50

resources:
  limits:
    cpu: 1000m
    memory: 1Gi
  requests:
    cpu: 500m
    memory: 512Mi

autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPU: 80
```

**What this does:** Fixes all 7 production values:

1. **`replicaCount: 4`** (was 1) — production needs multiple replicas for high availability. Note: when autoscaling is enabled, the HPA manages replica count, but this value serves as the initial count.
2. **`logLevel: info`** (was debug) — debug logging in production generates massive log volume. `info` captures important events without noise. Use `warn` for even less noise.
3. **`databaseHost: production-db.internal`** (was staging-db.internal) — the most critical fix. Staging and production must use separate databases. Pointing production at the staging database can corrupt staging data or fail if the staging DB can't handle production load.
4. **`databaseName: api_production`** (was api_staging) — matches the production database name.
5. **`cacheEnabled: true`** (was false) — caching reduces database load in production. Without caching, every request hits the database, which becomes a bottleneck under traffic.
6. **`maxConnections: 50`** (was 10) — production handles more concurrent requests. A pool of 10 would exhaust instantly, causing connection wait timeouts.
7. **`resources`** — production gets 1000m CPU / 1Gi memory limits (was 250m / 256Mi). Undersized containers get throttled (CPU) or killed (OOM for memory).
8. **`autoscaling.enabled: true`** (was false) — enables the HPA to automatically scale pods based on CPU usage. With `minReplicas: 2` and `maxReplicas: 10`, production can handle traffic spikes without manual intervention.

### Step 4: Verify the staging values are still correct

```bash
cat values-staging.yaml
```

**What this does:** Confirms staging values are appropriate. Staging should have: 1 replica, debug logging (useful for development), staging database, no autoscaling, smaller resources. The existing staging file should already be correct.

### Step 5: Render and verify production

```bash
helm template webapp ./api-chart -f values-production.yaml
```

**What this does:** Renders the production resources. Check that you see:
- `replicas: 4` in the Deployment
- `DATABASE_HOST: "production-db.internal"` in the ConfigMap
- `LOG_LEVEL: "info"` in the ConfigMap
- `CACHE_ENABLED: "true"` in the ConfigMap
- A `HorizontalPodAutoscaler` resource (because `autoscaling.enabled: true`)
- Higher resource limits on the container

### Step 6: Render and verify staging

```bash
helm template webapp ./api-chart -f values-staging.yaml
```

**What this does:** Verifies staging still renders correctly. You should see:
- `replicas: 1`
- `DATABASE_HOST: "staging-db.internal"`
- `LOG_LEVEL: "debug"`
- No HPA resource (autoscaling disabled)

### Step 7: Deploy to the correct environment (if cluster available)

```bash
# For production:
helm upgrade --install webapp ./api-chart -f values-production.yaml -n production

# For staging:
helm upgrade --install webapp ./api-chart -f values-staging.yaml -n staging
```

**What this does:** `helm upgrade --install` either installs the chart (if it doesn't exist) or upgrades it (if it does). The `-f` flag specifies the values override file, and `-n` specifies the namespace.

## Docker Lab vs Real Life

- **Sealed values files:** In production, values files for different environments are stored in separate directories or repos. Some teams use tools like `helm-secrets` to encrypt sensitive values (database passwords, API keys) in the values file.
- **ArgoCD / FluxCD:** In GitOps workflows, each environment has a separate Application manifest pointing to the correct values file. ArgoCD detects drift between the values file and the running cluster.
- **Value precedence:** Helm applies values in order: chart defaults → first -f file → second -f file → --set flags. Later values override earlier ones. This allows layering: `base.yaml` → `production.yaml` → `--set image.tag=v2.1.1`.
- **Config drift detection:** In production, teams use `helm diff upgrade` to preview changes before applying. This catches cases where the values file has been accidentally modified.
- **Namespaces per environment:** Production and staging should be in separate namespaces (or separate clusters). This lab uses the same cluster for simplicity, but in production, cluster-level isolation is more secure.

## Key Concepts Learned

- **`helm install -f values-production.yaml` overrides base values** — the `-f` flag merges the override file on top of the chart's default `values.yaml`. Only the keys you specify in the override file are changed; everything else inherits from defaults.
- **Production and staging must have different database connections** — this seems obvious, but it's one of the most common configuration mistakes in real incidents. Always double-check database hostnames in production configs.
- **Debug logging in production is a real problem** — it generates massive log volume (10-100x more than info level), increases costs (CloudWatch/Datadog charges per GB), and makes it harder to find real errors in the noise.
- **Autoscaling requires appropriate resource requests** — the HPA calculates utilization as a percentage of CPU requests. If requests are too low, the HPA scales too aggressively; too high, and it never scales.
- **Helm values files are environment configuration** — treat them like infrastructure config. Review them carefully, version control them, and test them before deploying.

## Common Mistakes

- **Copy-pasting staging values to production and forgetting to change everything** — this is the exact mistake in this lab. Always use a checklist when creating environment-specific configs.
- **Forgetting to enable autoscaling for production** — without autoscaling, a traffic spike can overwhelm fixed replicas. The HPA is a safety net that prevents outages during load increases.
- **Setting resource limits too low for production** — containers that hit CPU limits get throttled (slow responses). Containers that hit memory limits get OOM-killed (crashes). Production resource limits should be based on load testing data.
- **Not testing the values override with `helm template`** — always render the chart with the production values file to verify the output before deploying. It takes 2 seconds and catches configuration errors.
- **Mixing up `-f` file order** — if you pass multiple `-f` flags, later files override earlier ones. `helm install -f base.yaml -f production.yaml` is correct. Reversing the order would override production values with base defaults.
