# Lab 039 — Helm Chart Won't Install
## Solution Walkthrough

---

## TLDR — Plain English Summary

Someone refactored a Helm chart for a web app, didn't test it, and then tried to deploy it. It broke. The chart has **9 bugs spread across 4 files** — some stop Helm from even reading the chart, some produce invalid Kubernetes resources, and one means the Service would never actually reach your pods even if everything else was fixed.

The core lesson: **Helm has its own layer of validation on top of Kubernetes.** A chart can fail before Kubernetes even sees it, or it can produce YAML that looks right but doesn't work. You need to know where each failure lives.

**The bugs:**
1. Chart.yaml: wrong Helm API version (`v1` instead of `v2`)
2. Chart.yaml: missing required `name` field
3. Chart.yaml: `appVersion` should be a quoted string
4. values.yaml: label value contains a space (Kubernetes rejects this)
5. values.yaml: service port is a string (`"80"`) instead of an integer
6. values.yaml: field name is `pullPolicy`, but the template references `imagePullPolicy` — a mismatch
7. deployment.yaml: missing closing `}}` brace in the image tag template
8. deployment.yaml: references `.Values.image.imagePullPolicy` which doesn't exist
9. service.yaml: Service selector uses `Release.Name` instead of `appLabel` — selector never matches the pods

**How to fix it:** Use `helm template` to surface errors without touching the cluster. Fix bugs one at a time, re-run after each fix, then install when rendering is clean.

---

## Background: What Is Helm and Why Does This Happen?

Helm is a package manager for Kubernetes. Instead of writing raw Kubernetes YAML, you write **templates** with variables, and Helm fills them in from a `values.yaml` file when you install the chart.

The failure chain here has two stages:
- **Stage 1 — Template rendering fails:** Helm tries to read the chart and convert templates into Kubernetes YAML. Any syntax error or missing required field stops this dead.
- **Stage 2 — Kubernetes rejects the output:** Helm successfully renders YAML, but the YAML violates Kubernetes rules (e.g. label with a space, port as a string).
- **Stage 3 — Resources exist but don't work:** Everything installs without errors, but the Service can't find the pods because the selector is wrong.

All three failure types are present in this lab.

---

## Investigative Learning Pathway

### Before You Start: Install Helm

This is the first lab using Helm. It is not installed by default on the Pi — install it first:

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

| Part | What it means |
|------|---------------|
| `curl` | Download the file from the URL |
| `\| bash` | Pipe it directly into bash to execute — the script auto-detects ARM64 and installs the correct binary |

Verify the install:
```bash
helm version
```

You should see `Version:"v3.x.x"`. Helm 3 is what this lab requires.

---

### Finding the Lab Directory

Your lab runner places charts inside the lab folder, not at the repo root. The chart is at:

```
k8s-labs/lab-039-helm-chart-broken/webapp-chart/
```

All `helm` commands in this lab use that full path:

```bash
helm template webapp ./k8s-labs/lab-039-helm-chart-broken/webapp-chart
```

---

### A Quick Sanity Check Tool: helm create

If you're ever unsure what a valid chart should look like, scaffold one:

```bash
helm create testchart
cat testchart/Chart.yaml
```

This generates a complete, correct chart with all required fields set properly — `apiVersion: v2`, a `name` field, quoted `appVersion`, working templates. Use it as a reference baseline. Delete when done:

```bash
rm -rf testchart
```

---

### Where Do You Start When a Helm Install Fails?

You've run:
```bash
helm install webapp ./k8s-labs/lab-039-helm-chart-broken/webapp-chart
```
And it's failed. Your instinct might be to jump into the YAML files immediately, but first — **do you know which layer is failing?** Is this a Helm template error, or did Kubernetes reject the resource?

**The first command to run is always:**
```bash
helm template webapp ./k8s-labs/lab-039-helm-chart-broken/webapp-chart
```

| Part | What it means |
|------|---------------|
| `helm` | The Helm CLI tool |
| `template` | Render the chart to YAML, but don't install anything |
| `webapp` | The release name you want to give this install |
| `./k8s-labs/lab-039-helm-chart-broken/webapp-chart` | Full path to the chart directory |

**Why this before anything else?** `helm template` is a dry run for rendering only. It shows every template error without touching your cluster. If `helm template` fails, the problem is in your chart files. If it succeeds, the problem is in what Kubernetes does with the output.

Run it and read the errors carefully. Helm usually tells you which file and line number broke.

---

### Step 1: Read the First Error — Chart.yaml

After running `helm template`, you'll see errors referencing `Chart.yaml`. This is always the first place Helm looks — it reads `Chart.yaml` to understand what kind of chart it's dealing with before processing anything else.

**The question to ask:** "What does Helm require from Chart.yaml, and does our file satisfy those requirements?"

Helm 3 has two mandatory fields in `Chart.yaml`:
- `apiVersion` — must be `v2` for Helm 3 charts
- `name` — the chart's identity; Helm can't do anything without it

Open the file:
```bash
cat ./k8s-labs/lab-039-helm-chart-broken/webapp-chart/Chart.yaml
```

| Part | What it means |
|------|---------------|
| `cat` | Print file contents to the terminal |
| `./k8s-labs/lab-039-helm-chart-broken/webapp-chart/Chart.yaml` | Full path to the chart metadata file |

**What you're looking for:** Is `apiVersion` set to `v2`? Is there a `name` field at all? Is `appVersion` quoted?

**How would I know `apiVersion: v1` is wrong?** Helm 3 was released in 2019 and changed the chart format. `v1` is the Helm 2 format. If you're running Helm 3 (which you are), `v1` charts either fail or behave unexpectedly. The error message from `helm template` will reference this explicitly.

**How would I know `name` is missing?** If the field simply isn't there, `helm template` throws a "missing required field 'name'" error. It's one of only two required fields.

**Fix Chart.yaml:**
```yaml
# BEFORE (broken)
apiVersion: v1        # Wrong for Helm 3
# name field missing entirely
appVersion: 1.0       # Float, not string

# AFTER (fixed)
apiVersion: v2
name: webapp
description: A web application chart
version: 1.0.0
appVersion: "1.0"     # Quoted — treated as string
type: application
```

**Why quote `appVersion`?** YAML without quotes interprets `1.0` as a floating-point number. Some Helm versions handle this fine, others don't. Quoting it (`"1.0"`) makes it unambiguously a string. Always quote values that look like numbers but should be treated as text.

Re-run after fixing:
```bash
helm template webapp ./k8s-labs/lab-039-helm-chart-broken/webapp-chart
```

---

### Step 2: New Errors — values.yaml

Once Chart.yaml is clean, `helm template` will proceed further and surface errors from the templates themselves, many of which trace back to `values.yaml`.

**The question to ask:** "Do the values in `values.yaml` satisfy what Kubernetes expects, and do the paths in the templates match the field names in the file?"

Open the file:
```bash
cat ./k8s-labs/lab-039-helm-chart-broken/webapp-chart/values.yaml
```

**Look at `appLabel`:**
```yaml
appLabel: "web app"   # Bug: space in label value
```

**How would I know this is wrong?** Kubernetes label values follow a strict rule: they must match the regex `[a-zA-Z0-9][-a-zA-Z0-9_.]*` and be no longer than 63 characters. A space is not in that character set. The Kubernetes API server will reject any resource with a space in a label value. This might not surface as a Helm error — it surfaces as a Kubernetes API rejection, which is a different layer.

**Look at `service.port`:**
```yaml
service:
  port: "80"   # Bug: string, not integer
```

**How would I know this is wrong?** Kubernetes Service manifests require port numbers to be integers. YAML treats `"80"` (with quotes) as a string. Helm passes it through unchanged, and the Kubernetes API server rejects the string.

**Look at the `pullPolicy` field:** The field is named `pullPolicy` in values.yaml, but — spoiler for the next step — the deployment template references `.Values.image.imagePullPolicy`. That extra `image` prefix makes it look for a non-existent nested field. We don't fix values.yaml here; we fix the template in Step 3.

**Fix values.yaml:**
```yaml
# BEFORE (broken)
appLabel: "web app"
service:
  port: "80"

# AFTER (fixed)
appLabel: "webapp"
service:
  type: ClusterIP
  port: 80
```

Re-run:
```bash
helm template webapp ./k8s-labs/lab-039-helm-chart-broken/webapp-chart
```

---

### Step 3: Template Errors — deployment.yaml

`helm template` now processes the templates. Errors here are Go template syntax errors or wrong value references.

Open the file:
```bash
cat ./k8s-labs/lab-039-helm-chart-broken/webapp-chart/templates/deployment.yaml
```

> **Editor note:** Use `nano` for edits on the Pi — `vi` has terminal compatibility issues over SSH. `Ctrl+O` → Enter to save, `Ctrl+X` to exit. Don't skip the Enter after `Ctrl+O` or nano won't write the file.

**Look at the image line:**
```yaml
image: "{{ .Values.image.repository }}:{{ .Values.image.tag }"
```

**How would I know the closing brace is missing?** Go templates use `{{ }}` — both sides need two braces. `{{ .Values.image.tag }` has a closing single brace only. `helm template` will throw a parse error: *"unexpected } in..."* or similar. The error message will point to the line number.

**Look at the imagePullPolicy line:**
```yaml
imagePullPolicy: {{ .Values.image.imagePullPolicy }}
```

**How would I know this reference is wrong?** Look at your values.yaml. The field is `image.pullPolicy`, not `image.imagePullPolicy`. Helm doesn't throw an error for this — Go templates silently render an empty string for missing values. The symptom is that `imagePullPolicy` is absent or empty in the rendered YAML, which may cause unexpected pod behaviour.

**How do you spot a missing-value bug vs a syntax bug?** Syntax bugs (`{{` without `}}`) will throw explicit errors. Missing-value bugs render silently as empty — you catch them by reading the rendered output carefully, or by knowing what should be there.

**Fix deployment.yaml:**
```yaml
# BEFORE (broken)
image: "{{ .Values.image.repository }}:{{ .Values.image.tag }"      # Missing }}
imagePullPolicy: {{ .Values.image.imagePullPolicy }}                  # Wrong path

# AFTER (fixed)
image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
imagePullPolicy: {{ .Values.image.pullPolicy }}
```

**Full corrected deployment.yaml:**
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

Re-run:
```bash
helm template webapp ./k8s-labs/lab-039-helm-chart-broken/webapp-chart
```

---

### Step 4: The Silent Bug — service.yaml

This is the most dangerous class of bug: **everything installs successfully, but the application doesn't work.** The Service exists, the pods exist, but traffic never reaches the pods.

Open the file:
```bash
cat ./k8s-labs/lab-039-helm-chart-broken/webapp-chart/templates/service.yaml
```

**Look at the selector:**
```yaml
selector:
  app: {{ .Release.Name }}    # Bug: wrong reference
```

**How would I know this is wrong?** A Service's `selector` must match the labels on the pods it should route to. Look at the Deployment template — pods are labelled with `app: {{ .Values.appLabel }}` (which resolves to `app: webapp`).

The Service selector resolves to `app: webapp` *only if the release name happens to also be `webapp`*. If you name your release differently — say, `helm install myapp ./webapp-chart` — the selector resolves to `app: myapp`, which matches nothing.

**How do you discover this in real life?** You install the chart, pods come up, then you try to reach the service and get no response. You run `kubectl get endpoints` and see the service has `<none>` — no backends. Then you compare `kubectl describe svc` (selector) against `kubectl describe pod` (labels). The mismatch is immediately visible.

**Fix service.yaml:**
```yaml
# BEFORE (broken)
selector:
  app: {{ .Release.Name }}

# AFTER (fixed)
selector:
  app: {{ .Values.appLabel }}
```

**Full corrected service.yaml:**
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

Re-run:
```bash
helm template webapp ./k8s-labs/lab-039-helm-chart-broken/webapp-chart
```

---

### Step 5: Verify the Chart Renders Cleanly

With all 9 bugs fixed, `helm template` should produce clean YAML — no errors, just a valid Deployment and Service manifest.

Read through the output carefully:
```bash
helm template webapp ./k8s-labs/lab-039-helm-chart-broken/webapp-chart
```

| Part | What it means |
|------|---------------|
| `helm` | The Helm CLI tool |
| `template` | Render without installing |
| `webapp` | The release name (appears as `{{ .Release.Name }}` in templates) |
| `./k8s-labs/lab-039-helm-chart-broken/webapp-chart` | Full path to the chart |

**What you're checking:** Does every field look right? Is `imagePullPolicy` present and set to `IfNotPresent`? Is the port an integer (`80`) not a string (`"80"`)? Does `appLabel` appear without spaces? Does the Service selector match the Deployment labels?

**Optionally, lint the chart:**
```bash
helm lint ./k8s-labs/lab-039-helm-chart-broken/webapp-chart
```

| Part | What it means |
|------|---------------|
| `helm` | The Helm CLI |
| `lint` | Run chart validation checks |
| `./webapp-chart` | Chart directory to validate |

This checks Chart.yaml structure, required fields, and common mistakes. It's less detailed than `helm template` for rendering errors but catches structural issues faster.

---

### Step 6: Install the Chart

Once rendering is clean, install:
```bash
helm install webapp ./k8s-labs/lab-039-helm-chart-broken/webapp-chart
```

| Part | What it means |
|------|---------------|
| `helm install` | Install a chart into the cluster |
| `webapp` | The release name — appears as `{{ .Release.Name }}` in templates |
| `./k8s-labs/lab-039-helm-chart-broken/webapp-chart` | The full chart path |

---

### Step 7: Verify the Deployment

```bash
kubectl get pods -l app=webapp
```

| Part | What it means |
|------|---------------|
| `kubectl get pods` | List pods |
| `-l app=webapp` | Filter to only pods with the label `app=webapp` |

```bash
kubectl get svc
```

| Part | What it means |
|------|---------------|
| `kubectl get svc` | List all Services in the current namespace |

```bash
kubectl get endpoints
```

| Part | What it means |
|------|---------------|
| `kubectl get endpoints` | Show the pod IPs that each Service is routing to |

**What you're checking:** Pods should be in `Running` state. The Service should exist. `endpoints` should show pod IPs (not `<none>`) — this confirms the selector is actually matching the pods.

---

## Lab vs Real Life

**`helm lint` in CI/CD** — In production, `helm lint` runs automatically in CI pipelines on every PR. It catches Chart.yaml issues and template syntax errors before anyone can deploy a broken chart.

**Chart testing (`ct`)** — The `chart-testing` tool goes further: it installs the chart into a test cluster and validates that resources come up healthy. Your Service selector bug would be caught here, whereas `helm lint` might not catch it.

**Schema validation (`values.schema.json`)** — Production charts include a JSON schema that validates `values.yaml` field types. A schema would have caught the `port: "80"` string/integer mismatch at lint time, before rendering.

**`helm diff`** — The `helm-diff` plugin is like `terraform plan` for Helm. Before upgrading a chart, it shows you exactly what would change in the cluster. Prevents surprise changes.

**Selector mismatches in real upgrades** — The Service selector bug is especially dangerous during chart refactors. If you change the label structure and the selector stops matching existing pods, traffic drops to zero silently. Always check endpoints after any label change.

---

## Key Concepts to Remember

- **`helm template` is your first tool, always** — dry run rendering with full error output, no cluster changes.
- **Helm 3 requires `apiVersion: v2` and `name` in Chart.yaml** — both mandatory, both fatal if missing.
- **Template references are exact paths** — `.Values.image.pullPolicy` and `.Values.image.imagePullPolicy` are completely different. No fuzzy matching, no helpful error.
- **Label values can't contain spaces** — strict regex rules, rejected at the Kubernetes API level.
- **Service selectors must match pod labels exactly** — a mismatch installs silently but serves nothing.
- **Some bugs fail loudly, some fail silently** — syntax errors throw immediately; wrong value references and selector mismatches hide until you look for them.

---

## Common Mistakes

**Fixing one bug and assuming the rest are fine.** Helm errors cascade — fix the first one and re-run. New errors often appear once earlier blocking errors are resolved.

**Confusing `version` and `appVersion` in Chart.yaml.** `version` is the chart's own version, used by Helm for chart management. `appVersion` is informational only — the version of the application the chart deploys. Updating one doesn't update the other.

**Not quoting strings in values.yaml.** YAML auto-types. `tag: 1.0` → float. `tag: "1.0"` → string. For image tags, always quote.

**Mismatching labels across templates.** The Deployment's `selector.matchLabels`, the pod's `template.metadata.labels`, and the Service's `selector` must all be identical. Any one being different breaks either pod scheduling or traffic routing.

**Using `{{ .Release.Name }}` where you mean `{{ .Values.xxx }}`** — Release.Name is the user-supplied release name at install time. It's not a label value you control. Labels should come from `values.yaml`.

---

## Reset — Running This Lab Again From Scratch

Helm state lives in the cluster (as Kubernetes secrets in the `helm` namespace), and the chart files live in your repo. To reset completely:

### Step 1: Uninstall the Helm release (if installed)
```bash
helm uninstall webapp
```

| Part | What it means |
|------|---------------|
| `helm uninstall` | Remove the release and all its Kubernetes resources |
| `webapp` | The release name used at install time |

**If you're not sure whether it was installed:**
```bash
helm list
```
This lists all installed releases. If `webapp` is not there, nothing to uninstall.

### Step 2: Restore broken chart files from Git
```bash
git checkout -- k8s-labs/lab-039-helm-chart-broken/
```

| Part | What it means |
|------|---------------|
| `git checkout --` | Restore files to their last committed state |
| `k8s-labs/lab-039-helm-chart-broken/` | The full lab directory to restore |

This returns all four files (`Chart.yaml`, `values.yaml`, `templates/deployment.yaml`, `templates/service.yaml`) to their original broken state. You're back at the start of the lab.

### Step 3: Confirm broken state is restored
```bash
helm template webapp ./k8s-labs/lab-039-helm-chart-broken/webapp-chart
```

You should see errors again. If you do, the lab is fully reset and ready to run from Step 1.

### Optional: Confirm no lingering Kubernetes resources
```bash
kubectl get all -l app=webapp
```

If this returns nothing, the cluster is clean. If resources linger after `helm uninstall`, delete them manually:
```bash
kubectl delete deployment webapp-webapp
kubectl delete svc webapp-webapp
```
