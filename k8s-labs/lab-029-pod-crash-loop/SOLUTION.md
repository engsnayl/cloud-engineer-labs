# Lab 29 — Solution Walkthrough: Pod CrashLoopBackOff

---

## TLDR — What's Going On Here?

A Kubernetes Deployment for a service called "payment-service" is broken. The pods keep crashing and restarting in a loop — Kubernetes calls this **CrashLoopBackOff**. It's like a car that keeps stalling every time you turn the key — the engine management system (Kubernetes) keeps trying to start it, but something is fundamentally wrong.

**There are three things wrong with the deployment file:**

1. **Resources are backwards** — The manifest asks for MORE resources than it's allowed to use (requests > limits). That's like saying "I need at least 256MB of RAM but you can only give me 128MB." Kubernetes rejects this at the door — it won't even create the pod.
2. **Wrong image tag** — It's trying to download a version of Nginx (1.99.0) that doesn't exist. Like ordering a car model that was never manufactured.
3. **Health check on the wrong port** — Kubernetes checks if the app is alive by poking port 8080, but Nginx actually listens on port 80. So Kubernetes thinks the app is dead and keeps killing it. Like knocking on the back door when the shop entrance is at the front.

**The fix:** Swap the resource values so requests are smaller than limits, change the image tag to `nginx:1.25`, and point the health check at port 80 with path `/`. Fix them one at a time to see how Kubernetes surfaces each error differently.

---

## Understanding the Deployment Manifest

Before fixing anything, here's what the broken YAML file actually means, line by line:

```yaml
apiVersion: apps/v1
```
**What it means:** "I'm using version 1 of the apps API." Kubernetes has different API versions for different resource types. Deployments live under `apps/v1`.

```yaml
kind: Deployment
```
**What it means:** "This file describes a Deployment." A Deployment tells Kubernetes to run and manage one or more copies of a container. If a pod dies, the Deployment creates a replacement automatically.

```yaml
metadata:
  name: payment-service
  labels:
    app: payment-service
```
**What it means:** The Deployment is called `payment-service`. Labels are key-value tags you attach to resources so you can find and filter them later — like putting a sticky note on a folder.

```yaml
spec:
  replicas: 1
```
**What it means:** "Run exactly 1 copy of this pod." If you set this to 3, Kubernetes would run 3 identical pods.

```yaml
  selector:
    matchLabels:
      app: payment-service
```
**What it means:** "This Deployment manages any pods that have the label `app: payment-service`." This is how the Deployment knows which pods belong to it.

```yaml
  template:
    metadata:
      labels:
        app: payment-service
```
**What it means:** "When creating new pods, give them the label `app: payment-service`." This must match the `selector` above — otherwise the Deployment creates pods it doesn't recognise as its own.

```yaml
    spec:
      containers:
      - name: payment-service
        image: nginx:1.99.0
```
**What it means:** "Run a container called `payment-service` using the `nginx:1.99.0` image from Docker Hub." This is like saying "install this specific version of the software." **BROKEN: version 1.99.0 doesn't exist.**

```yaml
        ports:
        - containerPort: 80
```
**What it means:** "This container listens on port 80." This is informational — it tells Kubernetes and other developers which port the app uses.

```yaml
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 3
```
**What it means:** "Every 3 seconds, send an HTTP GET request to port 8080 at the path `/healthz`. Wait 5 seconds before starting checks. If it fails enough times, kill the container and restart it." **BROKEN: Nginx listens on port 80, not 8080, and doesn't have a `/healthz` endpoint.**

```yaml
        resources:
          requests:
            memory: "256Mi"
            cpu: "500m"
          limits:
            memory: "128Mi"
            cpu: "250m"
```
**What it means:** Requests are the minimum guaranteed resources — the scheduler uses these to decide which node to place the pod on. Limits are the maximum the container can use. `500m` means 500 millicores (half a CPU core). `256Mi` means 256 mebibytes of RAM. **BROKEN: requests are bigger than limits, which is impossible.**

---

## Thought Process — How to Debug CrashLoopBackOff

When a pod is in CrashLoopBackOff, an experienced engineer uses a systematic approach:

1. **Check pod status** — `kubectl get pods` to see the current state.
2. **Describe the pod** — `kubectl describe pod <n>` for the Events section which tells you WHY it's failing.
3. **Check logs** — `kubectl logs <pod> --previous` shows logs from the last crashed container.
4. **Inspect the manifest** — check image tag, probes, resources, env vars, and volume mounts.

**Key insight:** CrashLoopBackOff means Kubernetes is doing its job — it detected a failure and is trying to restart the pod. The backoff delay increases with each restart (10s, 20s, 40s, up to 5 minutes). Fix the root cause, don't fight the restart mechanism.

---

## Step-by-Step Solution

We fix the three issues one at a time so you can see how Kubernetes surfaces each type of error differently.

### Step 1: Apply the Broken Manifest

```bash
kubectl apply -f manifests/broken/deployment.yaml
```

#### Command Breakdown

| Part | What It Does |
|------|-------------|
| `kubectl` | The Kubernetes command-line tool — your main way to talk to the cluster |
| `apply` | Create or update a resource. If it exists, update it. If not, create it |
| `-f` | Short for `--filename`. Tells kubectl to read the resource definition from a file |
| `manifests/broken/deployment.yaml` | Path to the YAML file containing the Deployment definition |

**What happens:** Kubernetes rejects the manifest immediately with an error:

```
The Deployment "payment-service" is invalid:
* spec.template.spec.containers[0].resources.requests: Invalid value: "500m": must be less than or equal to cpu limit of 250m
* spec.template.spec.containers[0].resources.requests: Invalid value: "256Mi": must be less than or equal to memory limit of 128Mi
```

Kubernetes catches the resources problem at the door — it won't even create the pod. The error tells you exactly what's wrong: requests exceed limits.

---

### Step 2: Fix Issue 1 — Resource Requests Exceed Limits

Open the manifest:

```bash
nano manifests/broken/deployment.yaml
```

#### Command Breakdown

| Part | What It Does |
|------|-------------|
| `nano` | A simple text editor. Arrow keys to navigate, works like a normal editor |
| `manifests/broken/deployment.yaml` | The file to edit |

Find the `resources:` section and swap the values:

**Before (broken):**
```yaml
        resources:
          requests:
            memory: "256Mi"
            cpu: "500m"
          limits:
            memory: "128Mi"
            cpu: "250m"
```

**After (fixed):**
```yaml
        resources:
          requests:
            memory: "128Mi"
            cpu: "250m"
          limits:
            memory: "256Mi"
            cpu: "500m"
```

Save with `Ctrl+O` (letter O), `Enter`, then `Ctrl+X` to exit.

Apply again:

```bash
kubectl apply -f manifests/broken/deployment.yaml
```

**What happens:** Kubernetes accepts the manifest this time — you'll see `deployment.apps/payment-service created`. But the pod won't be healthy yet because there are still two more issues.

---

### Step 3: Check Pod Status — Discover Issue 2

```bash
kubectl get pods -l app=payment-service
```

#### Command Breakdown

| Part | What It Does |
|------|-------------|
| `kubectl` | The Kubernetes CLI tool |
| `get pods` | List pod resources — shows name, status, restarts, and age |
| `-l` | Short for `--selector`. Filters resources by label |
| `app=payment-service` | Only show pods where the label `app` equals `payment-service` |

**What you'll see:** The pod in `ErrImagePull` or `ImagePullBackOff` status. Kubernetes accepted the Deployment but can't download the image.

Now describe the pod for details:

```bash
kubectl describe pod -l app=payment-service
```

#### Command Breakdown

| Part | What It Does |
|------|-------------|
| `kubectl` | The Kubernetes CLI tool |
| `describe` | Show detailed info about a resource — much more than `get` |
| `pod` | The resource type to describe |
| `-l app=payment-service` | Filter by label instead of specifying the exact pod name |

**What to look for:** In the Events section at the bottom, you'll see:

```
Failed to pull image "nginx:1.99.0": ... docker.io/library/nginx:1.99.0: not found
```

The key word is `not found` — that image tag doesn't exist on Docker Hub.

---

### Step 4: Fix Issue 2 — Non-Existent Image Tag

Open the manifest again:

```bash
nano manifests/broken/deployment.yaml
```

Find the `image:` line and change it:

**Before:** `image: nginx:1.99.0`

**After:** `image: nginx:1.25`

Save and apply:

```bash
kubectl apply -f manifests/broken/deployment.yaml
```

**What happens:** Kubernetes creates a new pod with the correct image. The old pod with the bad image will be terminated. But there's still one more issue lurking.

---

### Step 5: Check Pod Status — Discover Issue 3

```bash
kubectl get pods -l app=payment-service
```

**What you'll see:** The pod might briefly show `ContainerCreating` while it pulls the image, then it'll move to `CrashLoopBackOff` with restarts climbing rapidly.

Describe the pod:

```bash
kubectl describe pod -l app=payment-service
```

**What to look for:** In the Events section:

```
Liveness probe failed: Get "http://10.42.0.10:8080/healthz": dial tcp 10.42.0.10:8080: connect: connection refused
Container payment-service failed liveness probe, will be restarted
```

The container is actually running fine — Nginx is alive and serving on port 80. But the liveness probe is checking port 8080 at path `/healthz`, where nothing exists. Kubernetes thinks the container is dead and keeps killing and restarting it.

---

### Step 6: Fix Issue 3 — Liveness Probe on Wrong Port

Open the manifest:

```bash
nano manifests/broken/deployment.yaml
```

Find the `livenessProbe:` section and change two things:

**Before (broken):**
```yaml
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
```

**After (fixed):**
```yaml
        livenessProbe:
          httpGet:
            path: /
            port: 80
```

Save and apply:

```bash
kubectl apply -f manifests/broken/deployment.yaml
```

---

### Step 7: Verify Everything Is Working

Wait for the rollout to complete:

```bash
kubectl rollout status deployment/payment-service --timeout=60s
```

#### Command Breakdown

| Part | What It Does |
|------|-------------|
| `kubectl` | The Kubernetes CLI tool |
| `rollout status` | Watch a deployment update and wait until it's complete or fails |
| `deployment/payment-service` | The resource type/name — format is `type/name` |
| `--timeout=60s` | Give up waiting after 60 seconds. Prevents hanging forever if something is still broken |

Then check the pod:

```bash
kubectl get pods -l app=payment-service
```

**What you should see:** Status `Running`, Ready `1/1`, Restart Count `0`.

For the full picture:

```bash
kubectl describe pod -l app=payment-service
```

**Confirm all three fixes are in place:**
- Image: `nginx:1.25` — pulled successfully
- Liveness: `http-get http://:80/` — probing the right port and path
- Requests (250m/128Mi) < Limits (500m/256Mi) — resources make sense
- Events section shows only Normal events — no warnings, no failures

---

## Three Types of Kubernetes Errors (What This Lab Taught You)

By fixing the issues one at a time, you saw three different ways Kubernetes surfaces problems:

| Error Type | When It Appears | What Happens | How to Spot It |
|-----------|----------------|-------------|---------------|
| **API Validation Rejection** | Immediately on `kubectl apply` | Kubernetes refuses to create the resource at all | Error message in your terminal — the pod is never created |
| **ImagePullBackOff** | After the pod is created but before the container starts | Kubernetes can't download the container image | `kubectl get pods` shows `ImagePullBackOff` or `ErrImagePull` |
| **CrashLoopBackOff** | After the container starts running | The container starts but keeps getting killed and restarted | `kubectl get pods` shows `CrashLoopBackOff` with rising restart count |

---

## Lab vs Real Life

- **Image registries:** In production, you'd use a private registry (ECR, GCR, ACR) with image tags tied to CI/CD pipelines, not Docker Hub with manually typed version numbers.
- **Health check endpoints:** Production apps implement dedicated `/healthz` and `/readyz` endpoints that verify actual health — database connectivity, upstream dependencies — not just "is the process alive."
- **Readiness vs liveness probes:** This lab only uses a liveness probe. In production you'd also use a readiness probe to control when the pod receives traffic. Liveness failure restarts the pod; readiness failure removes it from the Service endpoints.
- **Resource right-sizing:** In production, you'd use Vertical Pod Autoscaler (VPA) or monitoring data (Prometheus + Grafana) to determine appropriate values based on actual usage.
- **Deployment strategies:** Production uses rolling updates with `maxSurge` and `maxUnavailable` settings to ensure zero-downtime deployments.

---

## Key Concepts Learned

- **`kubectl describe pod` is the most important debugging command** — the Events section tells you exactly why a pod is failing.
- **CrashLoopBackOff means Kubernetes is restarting a failing container** — the backoff delay increases exponentially. Fix the root cause, not the symptom.
- **Image tags must exist** — Kubernetes can't pull what doesn't exist. ImagePullBackOff is your clue the image reference is wrong.
- **Liveness probes must match the application** — wrong port or path means Kubernetes keeps killing a perfectly healthy container.
- **Resource requests must be ≤ limits** — requests are what the scheduler guarantees; limits are the maximum. Requesting more than the limit is logically impossible.
- **Kubernetes surfaces errors at different stages** — some are caught immediately (validation), some when pulling the image, and some only after the container starts running.

---

## Common Mistakes

- **Fixing only one issue** — there are three problems and all must be fixed. Fixing the image but leaving the wrong probe port means the pod will still crash-loop.
- **Deleting the pod instead of fixing the Deployment** — deleting the pod creates a new one from the same broken Deployment. Always fix the Deployment manifest.
- **Setting requests equal to limits** — while valid, this gives every pod exactly what it requested with no flexibility. In practice, requests should be typical usage and limits should be peak usage.
- **Not waiting for the rollout** — applying the fix and immediately checking might show the old pod still terminating. Use `kubectl rollout status` to wait.
- **Confusing ImagePullBackOff and CrashLoopBackOff** — ImagePullBackOff means the image can't be downloaded. CrashLoopBackOff means the container starts but then exits. The fixes are different.
