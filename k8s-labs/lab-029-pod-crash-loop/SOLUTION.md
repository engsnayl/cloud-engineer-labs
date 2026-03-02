# Solution Walkthrough — Pod CrashLoopBackOff

## The Problem

A Kubernetes Deployment for the `payment-service` is stuck in CrashLoopBackOff — pods keep starting, immediately crashing, and restarting in an endless cycle. Kubernetes reports dozens of restarts. There are **three issues** in the Deployment manifest:

1. **Non-existent image tag** — the container image is set to `nginx:1.99.0`, which doesn't exist on Docker Hub. Kubernetes can't pull the image, so the pod enters an `ImagePullBackOff` or `ErrImagePull` state.
2. **Liveness probe on wrong port** — the probe checks port 8080, but Nginx listens on port 80. Even if the image were valid and the container started, the liveness probe would fail every 3 seconds, and after a few failures, Kubernetes would kill and restart the pod — causing a crash loop.
3. **Resource requests exceed limits** — the manifest requests 256Mi of memory and 500m CPU, but sets limits of only 128Mi and 250m. In Kubernetes, requests must be less than or equal to limits. This is invalid and will be rejected by the API server or cause unpredictable scheduling behavior.

## Thought Process

When a pod is in CrashLoopBackOff, an experienced Kubernetes engineer uses a systematic approach:

1. **`kubectl get pods`** — see the current state. CrashLoopBackOff, ImagePullBackOff, and Error are the most common problem states.
2. **`kubectl describe pod <name>`** — the Events section at the bottom tells you why the pod is failing. Look for "Failed to pull image," "Liveness probe failed," or "Back-off restarting failed container."
3. **`kubectl logs <pod> --previous`** — shows logs from the last crashed container. If the container never started (image pull failure), there won't be any logs.
4. **Inspect the manifest** — check the image tag, probe configuration, resource definitions, environment variables, and volume mounts.

The key insight with CrashLoopBackOff: Kubernetes is doing its job — it detected a failure and is trying to restart the pod. The backoff delay increases with each restart (10s, 20s, 40s, up to 5 minutes). The fix is to address the root cause, not to fight the restart mechanism.

## Step-by-Step Solution

### Step 1: Apply the broken manifest (if not already applied)

```bash
kubectl apply -f manifests/broken/deployment.yaml
```

**What this does:** Creates the Deployment with the broken configuration. Kubernetes will try to create the pod and you'll see it start failing.

### Step 2: Check the pod status

```bash
kubectl get pods -l app=payment-service
```

**What this does:** Lists pods with the label `app=payment-service`. You'll see the pod in `ErrImagePull`, `ImagePullBackOff`, or `CrashLoopBackOff` status, with a high restart count.

### Step 3: Describe the pod for detailed error info

```bash
kubectl describe pod -l app=payment-service
```

**What this does:** Shows detailed information including the Events section at the bottom. You'll see events like "Failed to pull image nginx:1.99.0" and "Error: ImagePullBackOff." The Events are the most important part — they tell you exactly what Kubernetes tried and what failed.

### Step 4: Fix the Deployment manifest

```bash
cat > manifests/broken/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payment-service
  labels:
    app: payment-service
spec:
  replicas: 1
  selector:
    matchLabels:
      app: payment-service
  template:
    metadata:
      labels:
        app: payment-service
    spec:
      containers:
      - name: payment-service
        image: nginx:1.25
        ports:
        - containerPort: 80
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 3
        resources:
          requests:
            memory: "128Mi"
            cpu: "250m"
          limits:
            memory: "256Mi"
            cpu: "500m"
EOF
```

**What this does:** Fixes all three issues:

1. **`image: nginx:1.25`** (was `nginx:1.99.0`) — uses a real, existing Nginx version that Kubernetes can pull from Docker Hub.
2. **`port: 80`** and **`path: /`** in the liveness probe (was port 8080 path /healthz) — now probes on the port Nginx actually listens on. The `/` path returns a 200 from Nginx's default page. The `/healthz` endpoint doesn't exist in stock Nginx.
3. **Requests ≤ limits** — swapped the values so requests (128Mi, 250m) are less than limits (256Mi, 500m). Requests are what the scheduler guarantees; limits are the maximum the container can use.

### Step 5: Apply the fixed manifest

```bash
kubectl apply -f manifests/broken/deployment.yaml
```

**What this does:** Updates the Deployment. Kubernetes will detect the changes, terminate the old failing pod, and create a new pod with the fixed configuration.

### Step 6: Wait for the pod to stabilize

```bash
kubectl rollout status deployment/payment-service --timeout=60s
```

**What this does:** Watches the Deployment rollout and waits until it's complete. A successful rollout means the new pod is running and passing its liveness probe. The `--timeout=60s` prevents waiting forever if something is still wrong.

### Step 7: Verify the pod is running and stable

```bash
kubectl get pods -l app=payment-service
```

**What this does:** Shows the pod status. It should show `Running` with `0` or very few restarts. If the restart count is under 3, the pod is stable.

## Docker Lab vs Real Life

- **Image registries:** In production, you'd use a private registry (ECR, GCR, ACR) with image tags tied to CI/CD pipelines, not Docker Hub with version numbers you type by hand. Image references would be like `123456789.dkr.ecr.us-east-1.amazonaws.com/payment-service:abc123`.
- **Health check endpoints:** Production applications should implement dedicated health check endpoints (`/healthz`, `/readyz`) that verify actual application health (database connectivity, upstream dependencies) rather than just "is the process alive." Nginx's default page isn't a real health check.
- **Readiness vs liveness probes:** This lab only uses a liveness probe. In production, you'd also use a readiness probe to control when the pod receives traffic. A liveness probe failure restarts the pod; a readiness probe failure removes it from the Service's endpoints.
- **Resource right-sizing:** In production, you'd use Vertical Pod Autoscaler (VPA) recommendations or monitoring data (Prometheus + Grafana) to determine appropriate resource requests and limits based on actual usage patterns.
- **Deployment strategies:** Production deployments use rolling updates with `maxSurge` and `maxUnavailable` settings to ensure zero-downtime deployments. If a new version is broken, Kubernetes automatically stops the rollout.

## Key Concepts Learned

- **`kubectl describe pod` is the most important debugging command** — the Events section tells you exactly why a pod is failing
- **CrashLoopBackOff means Kubernetes is restarting a failing container** — the backoff delay increases exponentially. Fix the root cause, not the symptom.
- **Image tags must exist** — Kubernetes can't pull an image that doesn't exist. Use `ImagePullBackOff` as a clue that the image reference is wrong.
- **Liveness probes must match the application** — if the probe checks the wrong port or path, Kubernetes will keep killing a perfectly healthy container
- **Resource requests must be ≤ limits** — requests are what the scheduler guarantees; limits are the maximum. Requesting more than the limit is logically impossible and will be rejected.

## Common Mistakes

- **Fixing only one issue** — there are three problems, and all must be fixed. Fixing the image but leaving the wrong probe port means the pod will still crash-loop (just with a different cause).
- **Using `kubectl delete pod` instead of fixing the Deployment** — deleting the pod creates a new one from the same broken Deployment. The new pod will have the same problems. Always fix the Deployment manifest.
- **Setting requests equal to limits** — while valid, this means every pod gets exactly what it requested with no flexibility. In practice, requests should be set to typical usage and limits to peak usage.
- **Not waiting for the rollout to complete** — applying the fix and immediately checking might show the old pod still terminating. Use `kubectl rollout status` to wait for the new pod to be ready.
- **Confusing ImagePullBackOff and CrashLoopBackOff** — `ImagePullBackOff` means the image can't be downloaded. `CrashLoopBackOff` means the container starts but then exits. The fixes are different.
