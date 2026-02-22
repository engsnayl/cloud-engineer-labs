# Solution Walkthrough — HPA Not Scaling

## The Problem

A Horizontal Pod Autoscaler (HPA) is configured to scale the `web-tier` deployment based on CPU usage, but it shows `<unknown>` for the current CPU metrics and won't scale. The HPA exists and the metric target is set (80% CPU), but it can't calculate a percentage because the deployment is **missing resource requests**.

The HPA calculates CPU utilization as: `(actual CPU usage / requested CPU) × 100%`. If no CPU request is defined, there's no denominator — the HPA can't compute a percentage and displays `<unknown>`. It's mathematically impossible for the HPA to work without resource requests.

## Thought Process

When an HPA shows `<unknown>` metrics, an experienced Kubernetes engineer checks:

1. **Is metrics-server running?** The HPA gets its data from the metrics API. Check with `kubectl top nodes` — if this fails, metrics-server isn't working.
2. **Does the deployment have resource requests?** HPA calculates utilization as a percentage of requests. No requests = no percentage = `<unknown>`.
3. **Is the HPA targeting the right deployment?** Check that `scaleTargetRef` matches the actual Deployment name.
4. **Wait for metrics to populate** — after fixing the requests, it takes 15-30 seconds for metrics to appear.

This is one of the most common HPA issues. People create an HPA, wonder why it doesn't scale, and don't realize that resource requests are a mandatory prerequisite.

## Step-by-Step Solution

### Step 1: Apply the broken manifests

```bash
kubectl apply -f manifests/broken/
```

**What this does:** Creates the Deployment (without resource requests) and the HPA.

### Step 2: Check the HPA status

```bash
kubectl get hpa web-tier-hpa
```

**What this does:** Shows the HPA status. You'll see `<unknown>/80%` in the TARGETS column — the current metric is unknown, and the target is 80%. The HPA can't make scaling decisions without knowing the current utilization.

### Step 3: Describe the HPA for more detail

```bash
kubectl describe hpa web-tier-hpa
```

**What this does:** Shows detailed HPA information including the Conditions section. You'll see a condition like "FailedGetResourceMetric" with a message explaining that the metrics can't be calculated because the pods don't have resource requests.

### Step 4: Check the deployment for resource requests

```bash
kubectl get deployment web-tier -o jsonpath='{.spec.template.spec.containers[0].resources}' && echo
```

**What this does:** Shows the resources section of the container spec. You'll see it's empty (`{}`) — no requests or limits are defined.

### Step 5: Add resource requests to the deployment

```bash
kubectl patch deployment web-tier --type='json' \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/resources","value":{"requests":{"cpu":"100m","memory":"128Mi"},"limits":{"cpu":"500m","memory":"256Mi"}}}]'
```

Or edit the file and reapply:

```bash
cat > manifests/broken/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-tier
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web-tier
  template:
    metadata:
      labels:
        app: web-tier
    spec:
      containers:
      - name: web
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "256Mi"
EOF
kubectl apply -f manifests/broken/deployment.yaml
```

**What this does:** Adds resource requests and limits to the deployment:
- **`requests.cpu: 100m`** — the pod guarantees it needs at least 100 millicores. The HPA will calculate utilization as `actual_usage / 100m × 100%`. At 80m usage, that's 80% — the scaling threshold.
- **`requests.memory: 128Mi`** — guarantees 128 mebibytes of memory
- **`limits`** — sets maximum resource usage to prevent runaway consumption

### Step 6: Wait for the new pods to roll out

```bash
kubectl rollout status deployment/web-tier --timeout=60s
```

**What this does:** Waits for the rolling update to replace the old pods (without requests) with new pods (with requests).

### Step 7: Wait for metrics to populate

```bash
sleep 30
kubectl get hpa web-tier-hpa
```

**What this does:** Waits 30 seconds for the metrics-server to collect data from the new pods, then checks the HPA. The TARGETS column should now show an actual percentage (like `2%/80%`) instead of `<unknown>/80%`.

### Step 8: Verify the HPA is working

```bash
kubectl describe hpa web-tier-hpa
```

**What this does:** Shows the HPA conditions. You should see "AbleToScale: True" and "ScalingActive: True" — the HPA is now functional and will scale based on CPU usage.

## Docker Lab vs Real Life

- **Metrics-server:** The HPA depends on metrics-server being installed and running. Most managed Kubernetes services (EKS, GKE, AKS) include metrics-server by default. For self-managed clusters, you need to install it separately.
- **Custom metrics:** In production, you might scale on custom metrics (requests per second, queue depth, latency) using the Prometheus Adapter or KEDA, not just CPU. CPU-based scaling is a good start but doesn't capture application-level load.
- **Scale-down behavior:** The HPA has configurable scale-down behavior (`behavior.scaleDown`) to prevent rapid scaling down. The default stabilization window is 5 minutes — the HPA waits 5 minutes of low usage before removing pods.
- **Resource request guidelines:** CPU requests should reflect typical usage. If a pod typically uses 50m and you request 100m, 50% utilization is normal. If you request 1000m, 5% utilization means the HPA would never scale. The request value directly affects when scaling triggers.
- **VPA and HPA together:** Some teams use VPA to automatically set correct resource requests, and HPA to scale horizontally. Be careful — VPA and HPA can conflict if both try to manage the same metric (CPU).

## Key Concepts Learned

- **HPA requires resource requests on the target deployment** — without requests, the HPA can't calculate utilization percentages and shows `<unknown>`
- **HPA utilization = actual usage / request × 100%** — the request value is the denominator. This is why requests are mandatory.
- **`kubectl describe hpa` explains why scaling isn't working** — the Conditions section gives specific error messages
- **Metrics take time to appear** — after adding resource requests, wait 15-30 seconds for metrics-server to collect data from the new pods
- **Resource requests affect scaling behavior** — lower requests make the HPA more sensitive (scales up sooner); higher requests make it less sensitive

## Common Mistakes

- **Creating an HPA without resource requests** — this is the exact mistake in this lab. The HPA silently shows `<unknown>` instead of giving an obvious error.
- **Setting CPU requests too high** — if you request 1 CPU but only use 50m, utilization is 5%. The HPA won't scale up until 80% of 1 CPU (800m) is used, which may never happen. Set requests close to typical usage.
- **Setting CPU requests too low** — if you request 10m but actually need 100m, the pod is using 1000% of its request. The HPA would try to scale to 12+ replicas when you only need 2. This wastes cluster resources.
- **Not checking if metrics-server is installed** — `kubectl top pods` should return usage data. If it errors, metrics-server isn't running and the HPA will never work.
- **Expecting instant scaling** — the HPA checks metrics every 15 seconds (by default) and has a stabilization window. Scaling isn't instant — it takes at least 15-30 seconds for scale-up and up to 5 minutes for scale-down.
