# Solution Walkthrough — Helm Chart Won't Install

## The Problem

A Helm chart for a web application has **multiple bugs** across several files that prevent it from rendering or installing. The chart was recently refactored and wasn't tested before the deployment attempt. `helm install webapp ./webapp-chart` fails with template errors, and even if you force past some errors, the resulting Kubernetes resources won't work correctly.

There are **9 bugs** spread across 4 files:

- **Chart.yaml:** Wrong API version, missing required `name` field
- **values.yaml:** Label with a space (invalid for Kubernetes), service port as string instead of integer, pullPolicy field name mismatch
- **templates/deployment.yaml:** Missing closing template brace, wrong values reference
- **templates/service.yaml:** Service selector doesn't match deployment labels

## Thought Process

When a Helm chart fails to install, an experienced engineer:

1. **Run `helm template` first** — this renders the templates without installing anything. It shows you every template error without touching the cluster.
2. **Fix errors one at a time** — template errors often cascade. Fix the first one, re-run, fix the next.
3. **Check Chart.yaml** — `apiVersion` and `name` are required fields. `apiVersion: v2` is required for Helm 3.
4. **Check values.yaml** — Kubernetes has strict rules about label values (no spaces, max 63 chars) and port types (must be integers in most contexts).
5. **Check template references** — every `{{ .Values.x.y }}` must match an actual path in values.yaml. A typo like `imagePullPolicy` vs `pullPolicy` silently renders as empty.
6. **Check selectors match** — the Service's selector must match the Deployment's labels, or the Service won't find any pods.

## Step-by-Step Solution

### Step 1: Try rendering the chart to see errors

```bash
helm template webapp ./webapp-chart
```

**What this does:** Renders all templates and shows errors. You'll see multiple errors including template parse failures and missing references. This is the starting diagnostic command for any Helm chart issue.

### Step 2: Fix Chart.yaml

The original `Chart.yaml` has three issues:

```yaml
# BROKEN
apiVersion: v1        # Wrong — Helm 3 requires v2
# Missing name field  # name is required
appVersion: 1.0       # Should be a string
```

Fix it:

```yaml
apiVersion: v2
name: webapp
description: A web application chart
version: 1.0.0
appVersion: "1.0"
type: application
```

**What this does:** Fixes three issues:
- **`apiVersion: v2`** — Helm 3 charts must use `apiVersion: v2`. The `v1` API version is for Helm 2 and is deprecated.
- **`name: webapp`** — the `name` field is mandatory in Chart.yaml. Without it, Helm can't identify the chart.
- **`appVersion: "1.0"`** — `appVersion` should be quoted as a string. Unquoted `1.0` is interpreted as a float, which can cause issues with some Helm versions.

### Step 3: Fix values.yaml

The original `values.yaml` has three issues:

```yaml
# BROKEN
appLabel: "web app"    # Space in label value — invalid for K8s
service:
  port: "80"           # String — should be integer
image:
  pullPolicy: IfNotPresent  # Correct here, but template references wrong name
```

Fix it:

```yaml
replicaCount: 2

image:
  repository: nginx
  tag: "1.25-alpine"
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80

resources:
  limits:
    cpu: 100m
    memory: 128Mi
  requests:
    cpu: 50m
    memory: 64Mi

appLabel: "webapp"
```

**What this does:** Fixes three issues:
- **`appLabel: "webapp"`** (was `"web app"`) — Kubernetes label values cannot contain spaces. Labels must match the regex `[a-zA-Z0-9][-a-zA-Z0-9_.]*`. A space causes the resource to be rejected by the API server.
- **`port: 80`** (was `"80"`) — Service port must be an integer, not a string. YAML treats `"80"` as a string literal. Helm passes this through to the manifest, and Kubernetes rejects string values for port fields.
- **`pullPolicy`** — the value is correct in values.yaml, but the template references the wrong path. We fix the template side in the next step.

### Step 4: Fix templates/deployment.yaml

The original template has two issues:

```yaml
# BROKEN
image: "{{ .Values.image.repository }}:{{ .Values.image.tag }"     # Missing closing braces
imagePullPolicy: {{ .Values.image.imagePullPolicy }}                # Wrong field name
```

Fix it:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-webapp
  labels:
    app: {{ .Values.appLabel }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ .Values.appLabel }}
  template:
    metadata:
      labels:
        app: {{ .Values.appLabel }}
    spec:
      containers:
      - name: webapp
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        imagePullPolicy: {{ .Values.image.pullPolicy }}
        ports:
        - containerPort: 80
        resources:
          {{- toYaml .Values.resources | nindent 10 }}
```

**What this does:** Fixes two issues:
- **`{{ .Values.image.tag }}`** (was `{{ .Values.image.tag }`) — Go templates require matching double braces `{{ }}`. A missing closing brace causes a template parse error that prevents the entire chart from rendering.
- **`{{ .Values.image.pullPolicy }}`** (was `{{ .Values.image.imagePullPolicy }}`) — the values.yaml defines the field as `pullPolicy`, not `imagePullPolicy`. This mismatch causes the template to render an empty value, which Kubernetes may reject or default unexpectedly.

### Step 5: Fix templates/service.yaml

The original template has a selector mismatch:

```yaml
# BROKEN
selector:
  app: {{ .Release.Name }}    # Doesn't match deployment labels
```

Fix it:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}-webapp
spec:
  type: {{ .Values.service.type }}
  ports:
  - port: {{ .Values.service.port }}
    targetPort: 80
    protocol: TCP
  selector:
    app: {{ .Values.appLabel }}
```

**What this does:** Changes the Service selector from `{{ .Release.Name }}` to `{{ .Values.appLabel }}`. The Deployment labels its pods with `app: {{ .Values.appLabel }}` (which resolves to `app: webapp`). The Service must use the same label to find those pods. Using `{{ .Release.Name }}` would resolve to the release name (e.g., `app: webapp` if the release happens to be named `webapp`), but that's fragile and doesn't match the actual pod labels.

### Step 6: Verify the chart renders cleanly

```bash
helm template webapp ./webapp-chart
```

**What this does:** Re-renders the chart. With all fixes applied, you should see clean YAML output with no errors — a valid Deployment and Service manifest.

### Step 7: Install the chart (if cluster is available)

```bash
helm install webapp ./webapp-chart
```

**What this does:** Installs the chart into the cluster. Helm creates the Deployment and Service, and Kubernetes schedules the pods.

### Step 8: Verify everything is running

```bash
kubectl get pods -l app=webapp
kubectl get svc
```

**What this does:** Confirms the pods are Running and the Service exists with the correct port and selector.

## Docker Lab vs Real Life

- **Chart linting:** In production, `helm lint ./webapp-chart` is run as part of CI/CD pipelines to catch Chart.yaml issues, missing values, and template errors before deployment.
- **Chart testing:** Tools like `helm test` and `chart-testing` (`ct`) validate charts in CI. They render templates, check for valid Kubernetes resources, and optionally install into a test cluster.
- **Schema validation:** Production charts often include a `values.schema.json` file that validates values.yaml against a JSON schema. This catches type errors (like port being a string) before rendering.
- **Helm diff:** The `helm-diff` plugin shows what would change before upgrading, similar to `terraform plan`. This prevents surprise changes in production.
- **Subcharts and dependencies:** Real charts often have dependencies on other charts (like a Redis or PostgreSQL subchart). Dependency issues add another layer of complexity beyond what this lab covers.

## Key Concepts Learned

- **`helm template` is the essential debugging command** — it renders templates without installing, showing all errors safely. Always start here.
- **Chart.yaml requires `apiVersion: v2` and `name` for Helm 3** — these are mandatory fields. Missing them causes immediate failure.
- **Template references must exactly match values.yaml paths** — `{{ .Values.image.pullPolicy }}` and `{{ .Values.image.imagePullPolicy }}` are completely different. There's no fuzzy matching.
- **Kubernetes label values can't contain spaces** — labels follow strict regex rules. Spaces, special characters, and values over 63 characters are rejected.
- **Service selectors must match Deployment labels** — if they don't match, the Service has no endpoints and traffic doesn't reach the pods.

## Common Mistakes

- **Fixing only some bugs and assuming the rest are fine** — Helm charts can have cascading errors. One fix may reveal new errors that were hidden. Always re-run `helm template` after each fix.
- **Confusing Chart.yaml `version` with `appVersion`** — `version` is the chart's version (Helm uses this for chart management). `appVersion` is the version of the application the chart deploys (informational only).
- **Not quoting strings in values.yaml** — YAML auto-types unquoted values. `tag: 1.0` becomes a float, not a string. `tag: "1.0"` is a string. For image tags, always quote.
- **Mismatching labels across templates** — the Deployment's `selector.matchLabels`, `template.metadata.labels`, and the Service's `selector` must all match. If any one is different, pods won't be selected.
- **Using `{{ .Release.Name }}` where `{{ .Values.xxx }}` is needed** — Release.Name is the Helm release name (user-provided at install time). Values come from values.yaml. They serve different purposes and shouldn't be confused.
