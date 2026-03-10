# Lab 036 — HPA Not Scaling: Solution Walkthrough

---

## TLDR — What's Going On Here (Plain English)

You've set up an **autoscaler** — a Kubernetes feature that automatically adds more pods when your app gets busy, and removes them when it's quiet. Think of it like a manager who hires more staff when the queue gets long.

But the autoscaler has a problem: it can't do its job.

To decide whether to scale up, it calculates **how hard each pod is working as a percentage**. For example: "This pod is using 75% of its CPU — that's close to the 80% limit, better add another one."

The problem is there's no percentage to calculate because nobody told Kubernetes **what this pod's normal/expected CPU usage is**. Without that baseline number (called a **resource request**), the maths simply can't be done. Kubernetes reports `<unknown>` instead of a percentage, and the autoscaler does nothing.

**The fix:** Add a `resources.requests.cpu` value to the deployment so Kubernetes has a denominator for its calculation. Once that's in place, the autoscaler wakes up and works as expected.

**Steps in brief:**
1. Apply the broken manifests and observe the HPA showing `<unknown>`
2. Describe the HPA to see the specific error message
3. Check the deployment — confirm there are no resource requests defined
4. Add resource requests and limits to the deployment
5. Wait for pods to roll out and metrics to populate (~30 seconds)
6. Verify the HPA is now showing a real percentage and is active

---

## The Problem

A Horizontal Pod Autoscaler (HPA) is configured to scale the `web-tier` deployment based on CPU usage, but it shows `<unknown>` for the current CPU metrics and won't scale. The HPA exists and the metric target is set (80% CPU), but it can't calculate a percentage because the deployment is **missing resource requests**.

The HPA calculates CPU utilisation as: `(actual CPU usage / requested CPU) × 100%`

If no CPU request is defined, there's no denominator — the HPA can't compute a percentage and displays `<unknown>`. It's mathematically impossible for the HPA to work without resource requests.

---

## Thought Process

When an HPA shows `<unknown>` metrics, an experienced Kubernetes engineer checks:

1. **Is metrics-server running?** The HPA gets its data from the metrics API. Check with `kubectl top nodes` — if this fails, metrics-server isn't working.
2. **Does the deployment have resource requests?** HPA calculates utilisation as a percentage of requests. No requests = no percentage = `<unknown>`.
3. **Is the HPA targeting the right deployment?** Check that `scaleTargetRef` matches the actual Deployment name.
4. **Wait for metrics to populate** — after fixing the requests, it takes 15–30 seconds for metrics to appear.

This is one of the most common HPA issues. People create an HPA, wonder why it doesn't scale, and don't realise that resource requests are a mandatory prerequisite.

---

## Step-by-Step Solution

### Step 1: Apply the broken manifests

```bash
kubectl apply -f manifests/broken/
```

| Part | What it does |
|---|---|
| `kubectl apply` | Creates or updates resources from a file or directory |
| `-f manifests/broken/` | Points to a directory — applies all `.yaml` files found inside it |

This creates the Deployment (without resource requests) and the HPA.

---

### Step 2: Check the HPA status

```bash
kubectl get hpa web-tier-hpa
```

| Part | What it does |
|---|---|
| `kubectl get` | Retrieves and displays one or more resources |
| `hpa` | The resource type — Horizontal Pod Autoscaler |
| `web-tier-hpa` | The name of the specific HPA to look up |

**What to expect:** You'll see `<unknown>/80%` in the TARGETS column. The left side is the current measured value (unknown), and the right side is the threshold (80%). The HPA can't make scaling decisions without a current value.

---

### Step 3: Describe the HPA for more detail

```bash
kubectl describe hpa web-tier-hpa
```

| Part | What it does |
|---|---|
| `kubectl describe` | Shows detailed information about a resource, including events and conditions |
| `hpa` | The resource type |
| `web-tier-hpa` | The name of the HPA |

**What to expect:** Look at the **Conditions** section. You'll see a condition like `FailedGetResourceMetric` with a message explaining that metrics can't be calculated because the pods don't have resource requests defined.

---

### Step 4: Check the deployment for resource requests

```bash
kubectl get deployment web-tier -o jsonpath='{.spec.template.spec.containers[0].resources}' && echo
```

| Part | What it does |
|---|---|
| `kubectl get deployment web-tier` | Fetches the `web-tier` deployment |
| `-o jsonpath='...'` | Outputs a specific field from the resource using a path expression |
| `.spec.template.spec.containers[0].resources` | Navigates to the `resources` block of the first container in the pod template |
| `&& echo` | Prints a newline after the output so the result doesn't run into the next prompt |

**What to expect:** You'll see `{}` — an empty object. No requests or limits are defined.

> **Useful to know — simpler alternative:**
> ```bash
> kubectl describe deployment web-tier | grep -A5 Resources
> ```
> This shows the same section in a more readable format. Use whichever feels more natural.

---

### Step 5: Add resource requests to the deployment

The cleanest approach is to edit the manifest file and reapply it:

```bash
nano manifests/broken/deployment.yaml
```

Update the container spec to include a `resources` block:

```yaml
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "256Mi"
```

Then reapply:

```bash
kubectl apply -f manifests/broken/deployment.yaml
```

**What each value means:**

| Field | Value | What it does |
|---|---|---|
| `requests.cpu` | `100m` | The pod guarantees it needs at least 100 millicores. The HPA uses this as the denominator: `actual ÷ 100m × 100%` |
| `requests.memory` | `128Mi` | Guarantees 128 mebibytes of memory are reserved for this pod |
| `limits.cpu` | `500m` | The pod cannot use more than 500 millicores — prevents runaway CPU consumption |
| `limits.memory` | `256Mi` | The pod cannot use more than 256Mi of memory |

> **A note on millicores:** `100m` means 100 millicores, or one-tenth of a CPU core. Kubernetes measures CPU in thousandths of a core. So `1000m = 1 core`, `500m = half a core`, `100m = one-tenth of a core`.

> **Useful to know — `kubectl patch` alternative:**
> If you don't want to edit files, you can patch the running deployment directly:
> ```bash
> kubectl patch deployment web-tier --type='json' \
>     -p='[{"op":"add","path":"/spec/template/spec/containers/0/resources","value":{"requests":{"cpu":"100m","memory":"128Mi"},"limits":{"cpu":"500m","memory":"256Mi"}}}]'
> ```
> This works, but it's complex to memorise and doesn't update your source file — so in practice, editing and reapplying the manifest is the better habit.

---

### Step 6: Wait for the new pods to roll out

```bash
kubectl rollout status deployment/web-tier --timeout=60s
```

| Part | What it does |
|---|---|
| `kubectl rollout status` | Watches and reports the progress of a deployment rollout |
| `deployment/web-tier` | Targets the `web-tier` deployment specifically |
| `--timeout=60s` | Exits with an error if the rollout hasn't completed within 60 seconds |

Kubernetes performs a rolling update — it replaces old pods (without resource requests) with new ones (with resource requests) one at a time, so there's no downtime.

---

### Step 7: Wait for metrics to populate

```bash
sleep 30
kubectl get hpa web-tier-hpa
```

| Part | What it does |
|---|---|
| `sleep 30` | Pauses for 30 seconds — gives the metrics-server time to collect data from the new pods |
| `kubectl get hpa web-tier-hpa` | Checks the HPA again now that metrics should be available |

**What to expect:** The TARGETS column should now show a real percentage (e.g., `2%/80%`) instead of `<unknown>/80%`.

---

### Step 8: Verify the HPA is working

```bash
kubectl describe hpa web-tier-hpa
```

**What to expect:** Look for these conditions:
- `AbleToScale: True` — the HPA has permission and ability to scale the deployment
- `ScalingActive: True` — the HPA is actively monitoring and will act on the metrics

The HPA is now functional and will scale based on CPU usage.

---

## Real World Context

- **Metrics-server is a dependency:** The HPA relies on metrics-server to get CPU data. Most managed Kubernetes platforms (EKS, GKE, AKS) include it by default. On self-managed clusters (like K3s on a Pi), you need to install it yourself.
- **CPU-based scaling is just the start:** In production, teams often scale on custom metrics — requests per second, queue depth, latency — using tools like KEDA or the Prometheus Adapter.
- **Scale-down is intentionally slow:** By default the HPA waits 5 minutes of sustained low usage before removing pods. This prevents thrashing (rapidly adding and removing pods).
- **Resource request accuracy matters:** If you set requests too high relative to actual usage, the HPA will rarely trigger. If too low, it may scale aggressively. Set requests close to typical usage.
- **VPA vs HPA:** Some teams use Vertical Pod Autoscaler (VPA) to automatically tune resource requests, and HPA to scale replicas. They can conflict if both are managing CPU — use with care.

---

## Key Concepts

- **HPA requires resource requests** — without them, the HPA can't calculate utilisation and shows `<unknown>`
- **HPA utilisation = actual usage ÷ request × 100%** — the request is the denominator; it's mandatory
- **`kubectl describe hpa` shows why scaling isn't working** — the Conditions section gives specific error messages
- **Metrics take time** — after adding resource requests, wait 15–30 seconds for metrics-server to collect fresh data
- **Resource request values directly affect scaling sensitivity** — lower requests = scales sooner; higher requests = scales later

---

## Common Mistakes

- **Creating an HPA without resource requests** — the HPA silently shows `<unknown>` rather than giving an obvious error. Easy to miss.
- **Setting requests too high** — if you request 1 CPU but only ever use 50m, utilisation will sit at ~5%. The HPA won't scale until usage hits 800m, which may never happen.
- **Setting requests too low** — if you request 10m but actually need 100m, the pod shows 1000% utilisation and the HPA tries to add a huge number of replicas.
- **Not checking metrics-server** — run `kubectl top pods` to confirm metrics are working. If it errors, metrics-server isn't running and the HPA will never function.
- **Expecting instant scaling** — the HPA checks every 15 seconds by default, and scale-down has a 5-minute stabilisation window. It's not instant.
