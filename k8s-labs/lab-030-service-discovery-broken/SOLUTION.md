# Solution Walkthrough — Service Discovery Broken

## The Problem

A Kubernetes Service called `backend-api` exists but has **no endpoints** — meaning it can't route traffic to any pods. The backend pods are running and healthy, but the Service doesn't know about them. When other pods try to reach `http://backend-api`, the connection is refused because the Service has no backends to forward traffic to.

There are **two issues** in the Service manifest:

1. **Label selector doesn't match pod labels** — the Service's selector says `app: backend` and `tier: api`, but the actual pods have labels `app: backend-api` and `tier: backend`. Since the selector doesn't match any pods, Kubernetes assigns zero endpoints to the Service.
2. **`targetPort` doesn't match the container port** — the Service says `targetPort: 8080`, but the Nginx containers inside the pods listen on port 80. Even if the selector matched, traffic would be forwarded to the wrong port and get "connection refused."

## Thought Process

When a Kubernetes Service doesn't work, an experienced engineer checks the label-selector-endpoint chain:

1. **Check endpoints** — `kubectl get endpoints backend-api`. If the endpoints list is empty (`<none>`), the Service selector doesn't match any pods.
2. **Compare selectors to labels** — `kubectl get svc backend-api -o yaml` shows the selector. `kubectl get pods --show-labels` shows the pod labels. They must match exactly — Kubernetes labels are case-sensitive and must match on every key-value pair.
3. **Check port mapping** — the Service's `targetPort` must match the `containerPort` in the pod spec. If they don't match, traffic reaches the pod but on the wrong port.
4. **Test from inside the cluster** — `kubectl run curl-test --image=curlimages/curl --rm -i --restart=Never -- curl -s http://backend-api` to verify end-to-end connectivity.

The key concept: Kubernetes Services use **label selectors** to find pods. A Service with selector `app: X` only routes traffic to pods that have the label `app: X`. It's not about names — it's about matching labels.

## Step-by-Step Solution

### Step 1: Apply the broken manifests (if not already applied)

```bash
kubectl apply -f manifests/broken/
```

**What this does:** Creates the Deployment (with 2 replicas of the backend pods) and the broken Service.

### Step 2: Check the Service endpoints

```bash
kubectl get endpoints backend-api
```

**What this does:** Shows the endpoints (pod IPs) that the Service is routing traffic to. You'll see `<none>` — the Service has no endpoints because its selector doesn't match any pods.

### Step 3: Compare the Service selector to pod labels

```bash
kubectl get svc backend-api -o jsonpath='{.spec.selector}' && echo
kubectl get pods --show-labels
```

**What this does:** Shows the Service's label selector and the pods' actual labels side by side. You'll see the mismatches:
- Service wants `app: backend` → pods have `app: backend-api`
- Service wants `tier: api` → pods have `tier: backend`

### Step 4: Check the port mapping

```bash
kubectl get svc backend-api -o jsonpath='{.spec.ports[0].targetPort}' && echo
kubectl get pods -l app=backend-api -o jsonpath='{.items[0].spec.containers[0].ports[0].containerPort}' && echo
```

**What this does:** Shows the Service's `targetPort` (8080) and the actual container port (80). These must match — the targetPort is where the Service forwards traffic to on each pod.

### Step 5: Fix the Service manifest

```bash
cat > manifests/broken/backend-service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: backend-api
spec:
  selector:
    app: backend-api
    tier: backend
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
EOF
```

**What this does:** Fixes both issues:

1. **`app: backend-api`** (was `backend`) and **`tier: backend`** (was `api`) — now matches the actual pod labels exactly. Kubernetes will find the pods and add them as endpoints.
2. **`targetPort: 80`** (was `8080`) — now matches the Nginx container port. Traffic forwarded to the pods will reach the Nginx server correctly.

### Step 6: Apply the fixed Service

```bash
kubectl apply -f manifests/broken/backend-service.yaml
```

**What this does:** Updates the Service with the corrected selector and port mapping. Kubernetes immediately re-evaluates which pods match and updates the endpoints.

### Step 7: Verify endpoints are populated

```bash
kubectl get endpoints backend-api
```

**What this does:** Shows the endpoints again. This time you should see 2 IP addresses (one for each replica), confirming the Service has found and connected to the backend pods.

### Step 8: Test connectivity from inside the cluster

```bash
kubectl run curl-test --image=curlimages/curl --rm -i --restart=Never -- curl -s http://backend-api
```

**What this does:** Spins up a temporary pod, runs `curl` against the Service, displays the result, and cleans up. You should see the Nginx welcome page or default response, proving end-to-end connectivity through the Service.

## Docker Lab vs Real Life

- **Service types:** This lab uses the default Service type (`ClusterIP`), which is only accessible from inside the cluster. In production, you might also use `NodePort` (accessible on each node's IP), `LoadBalancer` (provisions a cloud load balancer), or `ExternalName` (DNS alias).
- **Label conventions:** In production, labels follow conventions like the Kubernetes recommended labels: `app.kubernetes.io/name`, `app.kubernetes.io/version`, `app.kubernetes.io/component`. This prevents the exact kind of label mismatch seen in this lab.
- **Service mesh:** In large deployments, a service mesh (Istio, Linkerd) handles service discovery with more features — traffic splitting, retries, circuit breaking, mutual TLS. But the basic label-selector mechanism is the same underneath.
- **DNS resolution:** Inside a Kubernetes cluster, Services are reachable by name (e.g., `backend-api`) within the same namespace, or by fully-qualified name (`backend-api.default.svc.cluster.local`) from any namespace. This DNS is provided by CoreDNS.
- **Endpoint slices:** In modern Kubernetes (1.21+), EndpointSlices replace Endpoints for scalability. The concept is the same, but EndpointSlices handle large numbers of pods more efficiently.

## Key Concepts Learned

- **Kubernetes Services use label selectors, not names, to find pods** — the Service name and the pod name are unrelated. What matters is that the Service's `selector` labels match the pod's `metadata.labels`.
- **`kubectl get endpoints` is the key diagnostic** — if a Service has no endpoints, the selector doesn't match any pods. This is the single most common Service issue.
- **All selector labels must match** — if the selector has two labels, both must be present on the pod with exactly matching values. A partial match doesn't count.
- **`targetPort` must match `containerPort`** — the Service forwards traffic to the targetPort on each pod. If it doesn't match the port the application listens on, you get "connection refused."
- **Labels are case-sensitive** — `app: Backend` and `app: backend` are different labels. Always check for exact matches.

## Common Mistakes

- **Fixing only the selector or only the port** — both issues must be fixed. A correct selector with a wrong targetPort means the Service finds pods but can't reach the application inside them.
- **Adding the labels to the Service instead of fixing the selector** — labels on the Service itself are metadata for organizing Services. The `selector` field is what determines which pods receive traffic.
- **Confusing `port` and `targetPort`** — `port` is the port the Service listens on (what clients use). `targetPort` is the port on the pod the Service forwards to. They can be different, but `targetPort` must match `containerPort`.
- **Using `kubectl edit svc` and making a typo** — editing YAML in a terminal editor is error-prone. It's safer to fix the YAML file and re-apply with `kubectl apply`.
- **Not testing from inside the cluster** — Services are cluster-internal by default (`ClusterIP` type). You can't test them from outside the cluster with `curl` on your laptop. Use a temporary pod or `kubectl port-forward`.
