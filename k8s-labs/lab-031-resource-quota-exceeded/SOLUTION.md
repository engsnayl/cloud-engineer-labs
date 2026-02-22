# Solution Walkthrough — Resource Quota Exceeded

## The Problem

New deployments to the `production` namespace are being rejected with "exceeded quota" errors. A ResourceQuota limits the namespace to `2` CPU cores and `2Gi` memory for requests. The existing `legacy-service` deployment has 3 replicas, each requesting `500m` CPU and `512Mi` memory — that's `1500m` CPU and `1536Mi` memory total, consuming most of the quota. There isn't enough headroom left to deploy the `new-service`.

The challenge is to make room for `new-service` without deleting `legacy-service` — it must keep running. The solution is to **right-size** the legacy service by reducing its over-provisioned resource requests.

## Thought Process

When deployments are rejected by ResourceQuota, an experienced Kubernetes engineer:

1. **Check the quota** — `kubectl describe resourcequota -n production` shows the hard limits and current usage. This tells you exactly how much capacity is available.
2. **Identify over-provisioned workloads** — look at actual resource usage (`kubectl top pods`) vs requested resources. If a pod requests 500m CPU but uses 50m, it's over-provisioned.
3. **Right-size first, increase quota last** — increasing the quota is easy but defeats the purpose of having limits. The better approach is to reduce over-provisioned resource requests to match actual usage.
4. **Calculate the budget** — add up what's currently requested, subtract from the quota limit, and verify there's enough room for the new deployment.

## Step-by-Step Solution

### Step 1: Create the production namespace

```bash
kubectl create namespace production --dry-run=client -o yaml | kubectl apply -f -
```

**What this does:** Ensures the `production` namespace exists.

### Step 2: Apply the broken manifests

```bash
kubectl apply -f manifests/broken/
```

**What this does:** Creates the ResourceQuota, the legacy-service deployment, and attempts to create the new-service deployment. The new-service pods will fail to schedule because there's not enough quota.

### Step 3: Check the current quota usage

```bash
kubectl describe resourcequota production-quota -n production
```

**What this does:** Shows the hard limits and current usage. You'll see something like:
- `requests.cpu`: Used `1500m` of `2` (75%)
- `requests.memory`: Used `1536Mi` of `2Gi` (75%)

The remaining ~500m CPU and ~512Mi memory isn't enough for `new-service`, which requests `250m` CPU and `256Mi` per replica × 2 replicas = `500m` CPU and `512Mi` total. It's right at the edge, and Kubernetes may reject it due to how it calculates headroom.

### Step 4: Check the new-service deployment status

```bash
kubectl get deployment new-service -n production
kubectl describe deployment new-service -n production
```

**What this does:** Shows the deployment status. The Events section will show "exceeded quota" messages explaining that creating pods would exceed the namespace's resource limits.

### Step 5: Right-size the legacy service

```bash
kubectl patch deployment legacy-service -n production --type='json' \
    -p='[{"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/cpu","value":"200m"},
         {"op":"replace","path":"/spec/template/spec/containers/0/resources/requests/memory","value":"128Mi"},
         {"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/cpu","value":"400m"},
         {"op":"replace","path":"/spec/template/spec/containers/0/resources/limits/memory","value":"256Mi"}]'
```

Or edit the YAML file and reapply:

```bash
cat > manifests/broken/bloated-deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: legacy-service
  namespace: production
spec:
  replicas: 3
  selector:
    matchLabels:
      app: legacy-service
  template:
    metadata:
      labels:
        app: legacy-service
    spec:
      containers:
      - name: legacy
        image: nginx:1.25-alpine
        resources:
          requests:
            cpu: "200m"
            memory: 128Mi
          limits:
            cpu: "400m"
            memory: 256Mi
EOF
kubectl apply -f manifests/broken/bloated-deployment.yaml
```

**What this does:** Reduces the legacy service's resource requests from `500m`/`512Mi` to `200m`/`128Mi` per pod. With 3 replicas, total usage drops from `1500m`/`1536Mi` to `600m`/`384Mi`. This frees up significant quota for the new deployment.

### Step 6: Wait for legacy pods to roll out with new limits

```bash
kubectl rollout status deployment/legacy-service -n production --timeout=60s
```

**What this does:** Waits for the rolling update to complete. Kubernetes replaces each pod one by one with the new resource settings.

### Step 7: Check quota usage again

```bash
kubectl describe resourcequota production-quota -n production
```

**What this does:** Shows updated quota usage after right-sizing. The used values should be much lower, leaving room for new-service.

### Step 8: Trigger the new-service deployment

```bash
kubectl rollout restart deployment/new-service -n production
```

Or delete and re-apply:

```bash
kubectl apply -f manifests/broken/new-deployment.yaml
```

**What this does:** Retries the new-service deployment. Now that there's sufficient quota available, the pods should be created successfully.

### Step 9: Verify both deployments are running

```bash
kubectl get deployments -n production
```

**What this does:** Shows both deployments with their ready replica counts. Both `legacy-service` and `new-service` should have ready replicas.

## Docker Lab vs Real Life

- **ResourceQuota purpose:** In production, ResourceQuotas prevent a single team or namespace from consuming all cluster resources. They're essential in multi-tenant clusters where different teams share the same cluster.
- **LimitRange:** Production namespaces often also have a LimitRange, which sets default resource requests and limits for pods that don't specify them. This prevents pods from being created without resource constraints.
- **Vertical Pod Autoscaler (VPA):** In production, VPA can automatically recommend and adjust resource requests based on actual usage. This prevents the over-provisioning problem seen in this lab.
- **Monitoring actual usage:** Tools like Prometheus with Grafana (or Kubecost) show the gap between resource requests and actual usage. This helps identify over-provisioned workloads — pods that request far more than they use.
- **Right-sizing is an ongoing process:** Resource needs change as applications evolve. Regular review of request vs usage helps optimize cluster efficiency and cost.

## Key Concepts Learned

- **ResourceQuota limits total resource usage in a namespace** — it's a hard limit on the sum of all pods' resource requests and limits
- **`kubectl describe resourcequota` shows used vs available** — this is the key diagnostic for quota issues
- **Right-sizing is better than increasing quotas** — reducing over-provisioned requests frees up capacity without relaxing the guardrails
- **Resource requests vs limits:** requests are what the scheduler guarantees (and what quota counts); limits are the maximum a container can use
- **Over-provisioning wastes cluster capacity** — a pod requesting 500m CPU but using 50m wastes 450m of the namespace's quota budget

## Common Mistakes

- **Deleting the existing service to make room** — the challenge specifically says legacy-service must keep running. The right approach is to right-size, not remove.
- **Increasing the quota as the first option** — while this "works," it defeats the purpose of having quotas. Right-sizing is the better engineering practice.
- **Forgetting that quota counts requests, not actual usage** — even if a pod uses only 10m CPU, if it requests 500m, that's what counts against the quota.
- **Setting requests too low after right-sizing** — if you set requests lower than actual usage, the scheduler might place the pod on a node that can't handle it, leading to throttling or OOM kills. Requests should reflect actual typical usage.
- **Not checking if the new deployment needs to be re-triggered** — sometimes Kubernetes caches the quota rejection and doesn't automatically retry. You may need to restart the rollout.
