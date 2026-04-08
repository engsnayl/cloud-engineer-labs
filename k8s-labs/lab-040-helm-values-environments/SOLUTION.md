# Lab 040 — Wrong Config in Production (Helm Values)

---

## Plain-English TLDR

Someone copied the staging configuration file and used it as the production configuration. Production is now running with the wrong number of app copies (pods), the wrong database, debug-level logging that floods the logs, no caching, no auto-scaling, and far too little CPU and memory. None of these are code bugs — everything is in a single YAML file called `values-production.yaml`. The fix is to update that file with the values production actually needs, then verify the chart renders correctly before deploying.

---

## What Is Helm and Why Does This Matter?

Helm is the package manager for Kubernetes. You write a chart (a template) once and deploy it to multiple environments by providing different **values files**. The chart itself says things like "the database host is `{{ .Values.config.databaseHost }}`" — a placeholder. The values file fills in the actual value.

This means:
- The chart templates are correct and identical across environments
- The only difference between staging and production is the values file
- If the wrong values file is used — or if production values were never properly written — every environment-specific setting is wrong simultaneously

This lab simulates one of the most common real-world incidents: "production is down and we don't know why — turns out someone copied the staging values and forgot to update everything."

---

## Understanding the Files

Before diagnosing anything, it helps to understand what each file in this lab actually does and why it exists.

---

### `values-production.yaml` (the broken version)

This is the file you are fixing. In its broken state it is an exact copy of `values-staging.yaml`.

```yaml
replicaCount: 1
```
How many pod replicas Kubernetes should run. One means no redundancy — if the pod crashes, the service is completely down until Kubernetes restarts it. Production should always have at least 2–3 for high availability.

```yaml
config:
  logLevel: debug
```
The log verbosity level passed into the application as an environment variable. `debug` emits every internal function call, variable value, and request detail. In production this generates enormous log volume (10–100x more than `info`), inflates costs in log platforms like Datadog or CloudWatch (which charge per GB), and buries real errors in noise.

```yaml
  databaseHost: staging-db.internal
```
The hostname the application uses to connect to its database. This is a staging hostname — production traffic is currently hitting the staging database. This risks corrupting staging test data, or exhausting a database that was sized for low developer load.

```yaml
  databasePort: 5432
```
The port for the database connection. 5432 is the default PostgreSQL port. This value is correct and the same across environments.

```yaml
  databaseName: api_staging
```
The specific database schema to connect to. `api_staging` is the staging schema — production data lives in `api_production`. Even if you fixed the host, leaving the wrong database name would still connect to the wrong data.

```yaml
  cacheEnabled: false
```
Whether the application uses a cache layer (e.g. Redis) before hitting the database. With caching disabled, every single API request goes directly to the database. Under concurrent production traffic this creates a bottleneck — high latency, connection exhaustion, timeouts.

```yaml
  maxConnections: 10
```
The size of the database connection pool. A pool of 10 is fine for a single developer hitting staging. Under concurrent production requests, 10 connections exhaust in seconds. Requests that cannot get a connection queue up and time out.

```yaml
resources:
  limits:
    cpu: 250m
    memory: 256Mi
```
The maximum CPU and memory the container is allowed to use. `250m` is 250 millicores — a quarter of one CPU core. When a container hits its CPU limit, Kubernetes throttles it (slows it down). When it hits its memory limit, Kubernetes OOM-kills it (restarts it). Both are too low for production load.

```yaml
  requests:
    cpu: 100m
    memory: 128Mi
```
The amount of CPU and memory Kubernetes *reserves* for this container on the node. Requests affect scheduling — Kubernetes uses these to decide which node has capacity. They also affect HPA calculations: utilisation percentage = actual usage divided by requested amount.

```yaml
autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 3
  targetCPU: 80
```
Controls the HorizontalPodAutoscaler. When `enabled: false`, the HPA resource is not created at all — the `minReplicas`, `maxReplicas`, and `targetCPU` values are ignored entirely. Production needs autoscaling enabled so it can handle traffic spikes without manual intervention.

---

### `values-production.yaml` (the fixed version)

```yaml
replicaCount: 4
```
Four replicas gives production redundancy. If one pod crashes or is evicted, three remain serving traffic while Kubernetes brings the fourth back up. Note: when autoscaling is enabled, the HPA takes over replica management. `replicaCount` sets the initial count before the HPA first evaluates load — after that the HPA controls the number.

```yaml
config:
  logLevel: info
```
`info` logs significant application events — requests, errors, service start and stop — without the internal noise of debug. This is the standard production log level. Use `warn` if you want even less volume and only care about problems.

```yaml
  databaseHost: production-db.internal
```
The production database hostname. This is the most critical fix in the entire file — pointing production at the right database.

```yaml
  databaseName: api_production
```
The production database schema. Matches the schema that contains real production data.

```yaml
  cacheEnabled: true
```
Enables the cache layer. Frequently-requested data is served from cache rather than hitting the database on every request. This dramatically reduces database load and latency under traffic.

```yaml
  maxConnections: 50
```
A connection pool of 50 handles concurrent production traffic without exhausting connections. The right number depends on your database's `max_connections` setting and the number of replicas — in production this is tuned through load testing.

```yaml
resources:
  limits:
    cpu: 1000m
    memory: 1Gi
```
`1000m` = one full CPU core. `1Gi` = 1 gibibyte of memory. These limits give the application room to handle real production load without being throttled or OOM-killed.

```yaml
  requests:
    cpu: 500m
    memory: 512Mi
```
Requests are set to half the limits — a common pattern. This tells Kubernetes to reserve half a core and 512Mi per pod for scheduling, while allowing bursting up to the limit. The HPA scales when actual CPU usage exceeds 80% of 500m (400m per pod).

```yaml
autoscaling:
  enabled: true
  minReplicas: 2
  maxReplicas: 10
  targetCPU: 80
```
Enables the HPA. `minReplicas: 2` means there are always at least 2 pods running even at zero load — important for resilience. `maxReplicas: 10` is the ceiling. `targetCPU: 80` means the HPA adds pods when average CPU utilisation across all replicas exceeds 80% of their CPU requests.

---

### `values-staging.yaml`

This file is correct and should not change. It intentionally uses staging-appropriate values:

```yaml
replicaCount: 1       # Staging only needs one pod — no HA required
logLevel: debug       # Verbose logging is useful for developers debugging
databaseHost: staging-db.internal   # Correct staging database
cacheEnabled: false   # Caching can mask bugs in development — better to hit the real DB
maxConnections: 10    # Low traffic means a small pool is fine
autoscaling:
  enabled: false      # No need to autoscale a development environment
```

---

### `api-chart/templates/deployment.yaml`

The Deployment template defines how the application pods are run.

```yaml
{{- if not .Values.autoscaling.enabled }}
replicas: {{ .Values.replicaCount }}
{{- end }}
```
This is the key conditional. When autoscaling is enabled, the `replicas` field is intentionally omitted from the Deployment. This is correct Kubernetes practice — if both the Deployment and the HPA try to manage replicas, they fight each other. The HPA wins by convention, but having `replicas` hardcoded in the Deployment causes unnecessary churn on every reconciliation loop.

This conditional also caused the validator bug in this lab — the original `validate.sh` grepped the rendered template for `replicas: [3-9]`, which never appears when autoscaling is on. The fix is to check `replicaCount` directly from the values file instead.

```yaml
envFrom:
- configMapRef:
    name: {{ .Release.Name }}-config
```
Rather than hardcoding environment variables into the Deployment, the application reads them all from a ConfigMap. The ConfigMap is rendered from `values.yaml` via `configmap.yaml`. Configuration is separated from the container definition — this is the standard Kubernetes pattern.

---

### `api-chart/templates/hpa.yaml`

The HorizontalPodAutoscaler template is only rendered when `autoscaling.enabled: true`.

```yaml
{{- if .Values.autoscaling.enabled }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
spec:
  scaleTargetRef:
    kind: Deployment
    name: {{ .Release.Name }}-api
  minReplicas: {{ .Values.autoscaling.minReplicas }}
  maxReplicas: {{ .Values.autoscaling.maxReplicas }}
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: {{ .Values.autoscaling.targetCPU }}
{{- end }}
```

The HPA watches the Deployment and checks average CPU utilisation across all pods every 15 seconds (by default). If utilisation exceeds `targetCPU` percent of each pod's CPU request, it adds pods. If utilisation drops well below the target, it removes pods down to `minReplicas`.

---

### `api-chart/templates/configmap.yaml`

Translates the `config:` block from the values file into Kubernetes environment variables:

```yaml
data:
  LOG_LEVEL: "{{ .Values.config.logLevel }}"
  DATABASE_HOST: "{{ .Values.config.databaseHost }}"
  DATABASE_PORT: "{{ .Values.config.databasePort }}"
  DATABASE_NAME: "{{ .Values.config.databaseName }}"
  CACHE_ENABLED: "{{ .Values.config.cacheEnabled }}"
  MAX_CONNECTIONS: "{{ .Values.config.maxConnections }}"
```

All values are strings in a ConfigMap (note the quotes). The application container reads these as environment variables via `envFrom: configMapRef`. This is why `helm template` output is so useful for diagnosis — you can see the exact environment variables that will be injected into every pod.

---

## Real-Time Investigative Learning Pathway

### Step 1: You receive the ticket — what do you actually know?

You have been handed a ticket that says something like:

> "Production API is degraded. Slow responses, database errors, logs are enormous. Deployed last week after infrastructure refactor."

You do not know what the bug is yet. Start by asking: what changed recently? The ticket says "infrastructure refactor." That means configuration files, not application code. The first thing to check is whether the Helm values files for each environment are correct.

Navigate into the lab directory and orient yourself:

```bash
cd k8s-labs/lab-040-helm-values-environments
ls
```

What files do you see? You are looking for:
- The Helm chart directory (`api-chart/`)
- Values files for each environment (`values-staging.yaml`, `values-production.yaml`)

**Why this first?** Because reading both values files will immediately reveal whether production has been customised properly or just copied from staging.

---

### Step 2: Look at what is actually in both values files

Before touching anything, read both files:

```bash
cat values-production.yaml
cat values-staging.yaml
```

**What you are looking for:** Do they look the same? If production has `replicaCount: 1`, `logLevel: debug`, `staging-db.internal` — that is your answer. The production values were never updated.

**How would you know these values are wrong for production?**

- `replicaCount: 1` — one pod, no redundancy. If it crashes, the service is completely down.
- `logLevel: debug` — verbose logging in production is expensive, noisy, and a security risk.
- `staging-db.internal` as the database host — production traffic is hitting the staging database.
- `cacheEnabled: false` — every request goes straight to the database. Under load this causes slowness and connection exhaustion.
- `autoscaling.enabled: false` — traffic spikes will overwhelm fixed replicas with no ability to scale.
- Low resource limits — CPU throttling (slow responses) or OOM kills (crashes).

If you see all of these in `values-production.yaml`, you have found the root cause without touching a cluster.

---

### Step 3: Render the chart with production values to confirm

Reading the raw values file shows the inputs. Rendering the chart shows the actual Kubernetes resources that would be created. Do both.

```bash
helm template webapp ./api-chart -f values-production.yaml
```

| Part | What it does |
|------|-------------|
| `helm template` | Renders the chart locally — outputs the Kubernetes YAML that would be created, without deploying anything to a cluster |
| `webapp` | The release name Helm will use to label and track this deployment |
| `./api-chart` | Path to the chart directory containing `Chart.yaml`, `templates/`, and the default `values.yaml` |
| `-f values-production.yaml` | Override file — merges these values on top of the chart defaults. Keys in this file win over chart defaults. |

**What you are confirming in the output:**
- `DATABASE_HOST: "staging-db.internal"` in the ConfigMap — wrong database
- `LOG_LEVEL: "debug"` in the ConfigMap — wrong log level
- `CACHE_ENABLED: "false"` — no cache
- No `HorizontalPodAutoscaler` resource appearing — autoscaling is off
- Low CPU/memory in the container resource block

If you see all of this, the render confirms the values file is the root cause.

---

### Step 4: Render with staging values for comparison

```bash
helm template webapp ./api-chart -f values-staging.yaml
```

| Part | What it does |
|------|-------------|
| `helm template` | Same as above — renders locally, no deployment |
| `-f values-staging.yaml` | Now using the staging override file instead |

**What you are checking:** The staging output should look almost identical to the production output — because the production values were copy-pasted from staging and never changed. This confirms that both environments are currently running the same configuration.

In a healthy state, these two renders should look very different. Production should have higher resources, a different database, production log levels, and an HPA. If they look the same, you have confirmed the problem.

---

### Step 5: Fix the production values file

Now you know exactly what needs changing. Replace `values-production.yaml` with correct production values:

```bash
cat > values-production.yaml << 'EOF'
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
EOF
```

| Part | What it does |
|------|-------------|
| `cat >` | Writes output directly to a file, overwriting its current contents |
| `<< 'EOF'` | Heredoc — everything between this and the closing `EOF` is treated as the input. Single-quoted `'EOF'` prevents variable interpolation, which matters when the content contains `$` characters. |

**Why each value matters:**

| Setting | Was | Now | Why it matters |
|---------|-----|-----|----------------|
| `replicaCount` | 1 | 4 | One pod = no redundancy. When autoscaling is enabled, the HPA manages replicas — this value sets the initial count before the HPA takes control. |
| `logLevel` | debug | info | Debug logging generates 10–100x the volume of info-level, inflating costs and burying real errors. |
| `databaseHost` | staging-db.internal | production-db.internal | The most critical fix. Production traffic hitting the staging database risks data corruption. |
| `databaseName` | api_staging | api_production | Matches the correct schema on the production host. |
| `cacheEnabled` | false | true | Without a cache, every request hits the database — a bottleneck under concurrent production traffic. |
| `maxConnections` | 10 | 50 | 10 connections exhaust instantly under concurrent load. Requests queue and time out. |
| `resources.limits.cpu` | 250m | 1000m | 250m (quarter core) throttles under real load. 1000m = one full core. |
| `resources.limits.memory` | 256Mi | 1Gi | 256Mi gets OOM-killed under production load, causing constant pod restarts. |
| `autoscaling.enabled` | false | true | Enables the HPA to scale between `minReplicas` and `maxReplicas` based on CPU load. |

**A note on CPU units:** `250m` means 250 millicores — a quarter of one CPU core. `1000m` equals one full core. You can also write `1` instead of `1000m` — they are equivalent.

**A note on memory units:** `256Mi` means 256 mebibytes. `1Gi` means 1 gibibyte. Kubernetes uses binary-based units, not decimal megabytes.

---

### Step 6: Verify the fix — render production again

```bash
helm template webapp ./api-chart -f values-production.yaml
```

**What you are looking for in the output now:**
- `DATABASE_HOST: "production-db.internal"` in the ConfigMap ✓
- `LOG_LEVEL: "info"` in the ConfigMap ✓
- `CACHE_ENABLED: "true"` in the ConfigMap ✓
- `MAX_CONNECTIONS: "50"` in the ConfigMap ✓
- A `HorizontalPodAutoscaler` resource now appearing ✓
- `cpu: 1000m` and `memory: 1Gi` in the container limits ✓
- Note: `replicas` will **not** appear in the Deployment — this is correct. When autoscaling is enabled, the HPA owns replica count and the Deployment intentionally omits the field.

---

### Step 7: Verify staging is untouched

```bash
helm template webapp ./api-chart -f values-staging.yaml
```

**Why check staging?** When editing config files, it is easy to accidentally touch the wrong file. Confirm staging still renders correctly:
- `replicas: 1` in the Deployment — autoscaling is off for staging so this appears
- `DATABASE_HOST: "staging-db.internal"` — correct staging DB
- `LOG_LEVEL: "debug"` — correct for staging
- No HPA resource — autoscaling disabled for staging

If staging is clean, you are ready to validate.

---

### Step 8: Run the validator

```bash
cd ~/cloud-engineer-labs
lab validate 040
```

All 8 checks should now pass.

---

### Step 9: Deploy to the correct environments (if cluster available)

```bash
# Deploy to production
helm upgrade --install webapp ./api-chart -f values-production.yaml -n production

# Deploy to staging
helm upgrade --install webapp ./api-chart -f values-staging.yaml -n staging
```

| Part | What it does |
|------|-------------|
| `helm upgrade` | Updates an existing Helm release with new chart or values |
| `--install` | If the release does not exist yet, install it rather than erroring. Makes the command idempotent — safe to run in CI/CD pipelines. |
| `webapp` | The release name — Helm tracks history and state under this name |
| `./api-chart` | The chart to deploy |
| `-f values-production.yaml` | Override values file for this environment |
| `-n production` | Deploy into the `production` Kubernetes namespace, isolating it from staging on the same cluster |

**Why `-n production`?** Without specifying a namespace, both releases land in `default` and the second deploy would overwrite the first.

---

## Validator Bug — Documented

The original `validate.sh` checked for production replicas by grepping the rendered template output:

```bash
echo "$prod" | grep -q "replicas: [3-9]\|replicas: [1-9][0-9]"
```

This fails when `autoscaling.enabled: true` because the Deployment template conditionally omits the `replicas` field:

```yaml
{{- if not .Values.autoscaling.enabled }}
replicas: {{ .Values.replicaCount }}
{{- end }}
```

This is intentional and correct Kubernetes practice — the HPA owns replica count when autoscaling is enabled. Having `replicas` hardcoded in the Deployment causes reconciliation conflicts.

**Fix applied in `validate.sh`:** Check `replicaCount` directly from the values file:

```bash
grep -qE "replicaCount: ([3-9]|[1-9][0-9])" values-production.yaml
```

---

## Lab vs Real Life

| Lab | Real Production |
|-----|----------------|
| You edit `values-production.yaml` directly | Values files are version-controlled in Git. A PR with peer review is required before changes are merged. |
| You deploy by running `helm upgrade` manually | In GitOps pipelines (ArgoCD, FluxCD), a merge to main triggers automatic deployment. |
| Secrets like database passwords are in plaintext | Tools like `helm-secrets` or External Secrets Operator encrypt sensitive values and inject them at deploy time. |
| One cluster is used for both environments | Production typically runs on a separate cluster entirely — cluster-level isolation is more secure than namespace isolation. |
| You run `helm template` manually to verify | Pipelines run `helm diff upgrade` — shows a diff against the running state, not just the rendered output. |
| Environment configs sit next to each other | Config for different environments often lives in separate repos with different access permissions. |

---

## Key Concepts Recap

- **Helm values files are environment configuration.** They control everything about how the application runs without touching application code. Version control them, review them, and always test with `helm template` before deploying.
- **`helm template` is free and fast.** It renders the chart locally with zero cluster interaction. Run it to verify values before every deploy.
- **The `-f` flag merges, not replaces.** Helm layers values: chart defaults → `-f` files in order → `--set` flags. Each layer overrides the previous. This enables base config layered with environment-specific overrides.
- **When autoscaling is enabled, `replicas` is absent from the Deployment.** This is correct — the HPA owns replica count. Do not be alarmed when you do not see it in `helm template` output.
- **Debug logging in production is an incident in itself.** Always confirm `logLevel` is `info` or `warn` before deploying.
- **Wrong database host = data corruption risk.** One of the most common real-world configuration incidents. Always double-check database hostnames in production configs.

---

## Cleanup / Reset

To reset the lab to its broken starting state so it can be re-run from Step 1:

```bash
# Revert values-production.yaml to the broken staging-copy version
git checkout values-production.yaml

# If deployed to a cluster, remove both releases
helm uninstall webapp -n production
helm uninstall webapp -n staging
```

| Part | What it does |
|------|-------------|
| `git checkout values-production.yaml` | Restores the file to the last committed (broken) state without touching any other files |
| `helm uninstall webapp -n production` | Removes the Helm release and all Kubernetes resources it created from the production namespace |
| `helm uninstall webapp -n staging` | Same for staging |
