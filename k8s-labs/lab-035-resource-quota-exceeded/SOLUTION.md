# Lab 035 — Resource Quota Exceeded

## TLDR — Plain English Summary

Imagine a shared office where each team is given a fixed budget of desk space. Your team already has three people at big desks, using up most of the budget. Now a new colleague needs a desk, but there's no room left — even though your existing team members aren't actually using all the space their desks take up.

The fix isn't to knock down walls (increase the quota) — it's to swap the oversized desks for smaller ones that match what people actually need. Once you right-size the existing desks, there's plenty of room for the new colleague.

That's exactly what this lab does. Kubernetes is using a **ResourceQuota** to enforce a limit on CPU and memory for the `production` namespace. The existing `legacy-service` has three pods, each claiming way more CPU and memory than they actually use. This leaves no room for `new-service` to start. The solution is to reduce (right-size) the legacy service's resource requests so both services can run comfortably within the quota.

**In short:**
1. Create the namespace and apply the quota first — order matters
2. Apply the over-provisioned legacy-service — it fills most of the quota
3. Try to apply new-service — it gets blocked
4. Right-size legacy-service using the fixed manifest
5. Nudge new-service to retry — both services are now running

---

## The Problem

New deployments to the `production` namespace are being rejected with "exceeded quota" errors. A ResourceQuota limits the namespace to `2` CPU cores and `2Gi` memory for requests.

The existing `legacy-service` has 3 replicas, each requesting `600m` CPU and `512Mi` memory — totalling `1800m` CPU and `1536Mi` memory. That consumes most of the quota, leaving only `200m` CPU — not enough for `new-service`, which needs `500m` CPU across its 2 replicas.

The challenge: make room for `new-service` **without deleting `legacy-service`** — it must keep running. The solution is to right-size the legacy service by reducing its over-provisioned resource requests.

---

## Manifest Structure

This lab uses two folders:

```
manifests/
├── broken/
│   ├── quota.yaml               # The ResourceQuota — apply this first
│   ├── bloated-deployment.yaml  # legacy-service over-provisioned at 600m per pod
│   └── new-deployment.yaml      # new-service — will be blocked by quota
└── fixed/
    └── legacy-service.yaml      # legacy-service right-sized at 200m per pod
```

> **Important:** Apply order matters on K3s. If you apply everything at once, pods may schedule before the quota is active. Always apply the quota first, then the deployments separately.

---

## Thought Process

When deployments are rejected by ResourceQuota, an experienced Kubernetes engineer:

1. **Check the quota** — `kubectl describe resourcequota` shows hard limits and current usage. This tells you exactly how much capacity remains.
2. **Identify over-provisioned workloads** — compare actual resource usage (`kubectl top pods`) against requested resources. A pod requesting `600m` CPU but using `50m` is wasteful.
3. **Right-size first, increase quota last** — bumping the quota is easy but defeats the purpose of having limits. Reducing over-provisioned requests is the better engineering habit.
4. **Calculate the budget** — add up current requests, subtract from the hard limit, verify enough remains for the new deployment.

---

## Step-by-Step Solution

### Step 1: Check the namespace exists, create it if not

```bash
kubectl get namespaces
```

**What this does:** Lists all namespaces currently in the cluster. You should see `default`, `kube-system`, `kube-public`, and `kube-node-lease`. If `production` isn't there, create it:

```bash
kubectl create namespace production
```

**Command breakdown:**

| Part | What it does |
|------|-------------|
| `kubectl create` | Create a new resource in the cluster |
| `namespace` | The type of resource to create |
| `production` | The name to give it |

> **Useful pattern to know:** In scripts and automation you'll often see `kubectl create namespace production --dry-run=client -o yaml | kubectl apply -f -` — this is safe to run even if the namespace already exists. For interactive lab work, a simple get-then-create is clearer.

---

### Step 2: Apply the quota first

```bash
kubectl apply -f manifests/broken/quota.yaml
```

**Command breakdown:**

| Part | What it does |
|------|-------------|
| `kubectl apply` | Create or update resources from a file |
| `-f manifests/broken/quota.yaml` | The specific file to apply |

**What this does:** Creates the ResourceQuota object in the `production` namespace. This must exist and be active before the deployments are submitted — otherwise Kubernetes has nothing to enforce against and pods slip through unchecked.

Verify it's active:

```bash
kubectl get resourcequota -n production
```

You should see `requests.cpu: 0/2` — quota live, nothing used yet.

---

### Step 3: Apply the over-provisioned legacy-service

```bash
kubectl apply -f manifests/broken/bloated-deployment.yaml
```

**What this does:** Creates the `legacy-service` deployment with 3 replicas, each requesting `600m` CPU. Total: `1800m` — consuming 90% of the quota immediately, leaving only `200m` for anything else.

Check it's running:

```bash
kubectl get pods -n production
```

All 3 legacy-service pods should show `Running`.

---

### Step 4: Try to apply new-service — watch it get blocked

```bash
kubectl apply -f manifests/broken/new-deployment.yaml
```

**What to expect:** The deployment object gets created, but no pods appear. Kubernetes accepted the instruction but can't fulfil it — the quota won't allow the pods to be created.

Check the deployment status:

```bash
kubectl describe deployment new-service -n production
```

**Command breakdown:**

| Part | What it does |
|------|-------------|
| `kubectl describe` | Show detailed information about a resource including recent events |
| `deployment` | The type of resource to inspect |
| `new-service` | The specific deployment to look at |
| `-n production` | In the `production` namespace |

**What to look for in the output:**

```
Replicas: 2 desired | 0 available | 2 unavailable
ReplicaFailure: True   FailedCreate
```

This is the broken state. The deployment exists but has zero pods because the quota is rejecting them.

---

### Step 5: Check the quota usage

```bash
kubectl describe resourcequota production-quota -n production
```

**Command breakdown:**

| Part | What it does |
|------|-------------|
| `kubectl describe` | Show detailed information about a resource |
| `resourcequota` | The type of resource to inspect |
| `production-quota` | The name of the specific ResourceQuota object |
| `-n production` | In the `production` namespace |

**What to expect:**

```
requests.cpu:    1800m / 2000m    (90% used)
requests.memory: 1536Mi / 2Gi    (75% used)
```

Only `200m` CPU remaining — `new-service` needs `500m` (2 replicas × 250m). It simply doesn't fit.

---

### Step 6: Right-size the legacy service

The fix is in `manifests/fixed/legacy-service.yaml` — this is the corrected version with resource requests that reflect actual usage rather than over-provisioned guesses.

```bash
kubectl apply -f manifests/fixed/legacy-service.yaml
```

**What changes:**

| Resource | Before (per pod) | After (per pod) | Before × 3 replicas | After × 3 replicas |
|----------|-----------------|----------------|--------------------|--------------------|
| CPU request | 600m | 200m | 1800m | 600m |
| Memory request | 512Mi | 128Mi | 1536Mi | 384Mi |

This frees up `1200m` CPU and `1152Mi` memory — plenty of room for `new-service`.

**What happens next:** Kubernetes performs a rolling update — replacing legacy pods one at a time with the new right-sized versions. The service stays up throughout.

Watch the rollout:

```bash
kubectl rollout status deployment/legacy-service -n production --timeout=60s
```

**Command breakdown:**

| Part | What it does |
|------|-------------|
| `kubectl rollout status` | Watch a rolling update and report progress |
| `deployment/legacy-service` | The deployment to watch |
| `-n production` | In the `production` namespace |
| `--timeout=60s` | Give up and report failure if not complete within 60 seconds |

You'll see each pod being replaced in sequence — this is Kubernetes ensuring the service remains available throughout the update.

> **Useful to know:** You may also see `kubectl patch` used for this kind of change in documentation and scripts. It allows surgical in-place edits without touching a file. However it uses complex JSON Patch syntax that's difficult to memorise — editing the file and reapplying is the more natural real-world approach that also keeps your repo in sync with what's running in the cluster.

---

### Step 7: Check the quota again

```bash
kubectl describe resourcequota production-quota -n production
```

**What to expect:**

```
requests.cpu:    600m / 2000m    (30% used)
requests.memory: 384Mi / 2Gi    (18% used)
```

Plenty of headroom now exists for `new-service`.

---

### Step 8: Nudge new-service to retry

```bash
kubectl rollout restart deployment/new-service -n production
```

**Command breakdown:**

| Part | What it does |
|------|-------------|
| `kubectl rollout restart` | Force a fresh rollout of the deployment |
| `deployment/new-service` | The deployment to restart |
| `-n production` | In the `production` namespace |

> **Why is this needed?** Kubernetes doesn't automatically retry pods that previously failed due to quota. The deployment sits in a failed state until you nudge it. `rollout restart` is the cleanest way to do this.

---

### Step 9: Verify both deployments are running

```bash
kubectl get deployments -n production
```

**What to expect:**

```
NAME             READY   UP-TO-DATE   AVAILABLE
legacy-service   3/3     3            3
new-service      2/2     2            2
```

Final quota check:

```bash
kubectl describe resourcequota production-quota -n production
```

**What to expect:**

```
requests.cpu:    1100m / 2000m   (55% used)
requests.memory: 896Mi / 2Gi    (43% used)
pods:            5 / 10
```

Both services running comfortably within the quota. Lab complete.

---

## Pi / K3s Lab Notes

> These are infrastructure quirks specific to running this lab on a Raspberry Pi with K3s. They are not bugs in the lab — just things to be aware of so they don't cause confusion.

**Apply order is critical on K3s.** Unlike managed Kubernetes clusters, K3s on the Pi enforces quota with a slight delay. If you apply the quota and deployments together (`kubectl apply -f manifests/broken/`), pods may schedule before the quota becomes active — meaning both services start successfully and the lab scenario never triggers. Always apply in this order:

1. `quota.yaml` — verify it's active with `kubectl get resourcequota -n production`
2. `bloated-deployment.yaml` — wait for all 3 pods to show `Running`
3. `new-deployment.yaml` — separately, after legacy-service is fully up

**Rolling update deadlock.** If you try to right-size legacy-service while it's already consuming most of the quota, the rolling update can deadlock. Kubernetes tries to create a new right-sized pod before killing an old over-provisioned one — but there's no quota headroom to do so. The solution is to apply the manifest from `manifests/fixed/` which gives the rolling update enough room to proceed cleanly.

---

## Real World Context

- **ResourceQuota purpose:** In production, quotas prevent a single team or namespace from consuming all cluster resources. Essential in multi-tenant clusters where different teams share the same nodes — at a company like Tandem, different product teams or environments each get their own namespace with defined limits.
- **LimitRange:** Namespaces often also have a LimitRange alongside a ResourceQuota. LimitRange sets default requests and limits on pods that don't specify them — preventing unconstrained pods from slipping through altogether.
- **Vertical Pod Autoscaler (VPA):** VPA watches actual pod usage and automatically recommends or adjusts resource requests. It automates the right-sizing process you just did manually.
- **Monitoring the gap:** Tools like Prometheus + Grafana or Kubecost surface the difference between what pods request and what they actually use. That gap is wasted quota budget — identifying and closing it is a key cost optimisation activity.
- **Right-sizing is ongoing:** Resource needs shift as applications evolve. Regular review of request vs usage keeps cluster efficiency high and costs in check.

---

## Key Concepts

- **ResourceQuota limits total namespace usage** — it's a hard cap on the sum of all pod resource requests and limits in a namespace
- **`kubectl describe resourcequota` is the key diagnostic** — shows used vs available at a glance
- **Quota counts requests, not actual usage** — a pod using `10m` CPU but requesting `600m` costs `600m` against the quota
- **Right-sizing beats increasing limits** — freeing up capacity through accurate requests is better engineering than simply raising the ceiling
- **Requests vs limits:** requests are what the scheduler guarantees (and what quota counts); limits are the maximum a container can burst to
- **Apply order matters** — on K3s, quota must be active before deployments are submitted

---

## Common Mistakes

- **Applying everything at once** — on K3s, `kubectl apply -f manifests/broken/` applies quota and deployments simultaneously. Pods may schedule before the quota activates. Apply the quota file first, separately.
- **Deleting the existing service to make room** — the lab explicitly requires `legacy-service` to keep running. Right-size, don't remove.
- **Increasing the quota as the first fix** — this "works" but defeats the purpose of having quotas. Right-sizing is the correct approach.
- **Forgetting that quota counts requests, not actual usage** — even if a pod uses `10m` CPU, if it requests `600m`, that's what counts.
- **Setting requests too low after right-sizing** — requests below actual usage can cause throttling or OOM kills. Requests should reflect realistic typical usage, not the absolute minimum.
- **Not re-triggering new-service** — Kubernetes won't automatically retry a deployment that previously failed due to quota. Always run `kubectl rollout restart` after freeing up quota.
