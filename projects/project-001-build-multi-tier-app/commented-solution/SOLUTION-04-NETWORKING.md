# Solution Walkthrough: Part 4 — Networking

## What This Layer Does

Networking is the glue that connects everything. This layer handles two concerns:

1. **Ingress** — How does external traffic get routed to the right tier?
2. **NetworkPolicy** — How do we prevent unauthorized communication between tiers?

## Files in This Layer

| File | Purpose |
|------|---------|
| `k8s/ingress.yaml` | Routes external HTTP traffic to frontend and backend based on URL path |
| `k8s/network-policy.yaml` | Restricts database access to backend pods only |

## Ingress — The Front Door

### What Problem Does Ingress Solve?

Without Ingress, you'd need to either:
- **NodePort** — Expose each service on a high port (30000-32767) on every cluster node. Ugly URLs like `http://my-node:31234`
- **LoadBalancer** — Create a cloud load balancer per service. Gets expensive fast — one for frontend, one for backend, etc.

Ingress gives you **one entry point** with smart routing:
```
http://myapp.com/          → Frontend Service
http://myapp.com/api/data  → Backend Service
```

### How Ingress Works (Two Parts)

**Part 1: The Ingress Resource** (what we write in `ingress.yaml`)
This is just a declaration — "I want these routing rules." By itself, it does nothing.

**Part 2: The Ingress Controller** (a pod running in your cluster)
This is the actual reverse proxy that reads Ingress resources and configures routing. Common controllers:

| Controller | Used By | Notes |
|-----------|---------|-------|
| **NGINX Ingress Controller** | Most setups, minikube | Our choice |
| **Traefik** | k3s default | Auto-discovers services |
| **AWS ALB Ingress Controller** | EKS (AWS) | Creates real AWS ALBs |
| **GKE Ingress** | GKE (Google Cloud) | Uses Google Cloud Load Balancer |

You must install an Ingress Controller **before** Ingress resources do anything:
```bash
# minikube:
minikube addons enable ingress

# Or install via Helm:
helm install nginx-ingress ingress-nginx/ingress-nginx
```

### Path-Based Routing

```yaml
rules:
  - http:
      paths:
        - path: /api
          pathType: Prefix
          backend:
            service:
              name: backend
              port:
                number: 5000
        - path: /
          pathType: Prefix
          backend:
            service:
              name: frontend
              port:
                number: 80
```

The key concept is **most specific match wins**:
- `/api/health` → matches `/api` (more specific) → goes to backend
- `/api/data` → matches `/api` (more specific) → goes to backend
- `/favicon.ico` → matches `/` (only option) → goes to frontend
- `/` → matches `/` → goes to frontend

### Annotations — Controller-Specific Config

```yaml
annotations:
  kubernetes.io/ingress.class: nginx
  nginx.ingress.kubernetes.io/rewrite-target: /
```

Annotations are how you configure controller-specific behaviour. Different controllers have different annotations — `nginx.ingress.kubernetes.io/*` annotations only work with the NGINX Ingress Controller.

`rewrite-target: /` can affect how the path is forwarded to the backend. In simple setups like ours, the backend receives the original path (`/api/health`), which matches our Flask routes.

## NetworkPolicy — The Internal Firewall

### Default Kubernetes Networking: Wide Open

By default, **any pod can talk to any other pod** in the cluster. This is convenient but insecure:

```
Without NetworkPolicy:

Frontend pod ──can connect──► Database (BAD!)
Backend pod  ──can connect──► Database (OK)
Random pod   ──can connect──► Database (BAD!)
```

### Our NetworkPolicy: Least Privilege

```
With NetworkPolicy:

Frontend pod ──BLOCKED──► Database
Backend pod  ──ALLOWED──► Database (only on port 5432)
Random pod   ──BLOCKED──► Database
```

### How the Policy Works

```yaml
spec:
  podSelector:
    matchLabels:
      app: postgres        # This policy PROTECTS pods with this label
  policyTypes:
    - Ingress              # Controls INCOMING traffic
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: backend  # ONLY pods with this label can connect
      ports:
        - protocol: TCP
          port: 5432        # ONLY on this port
```

Three filters are applied — a connection must pass ALL of them:
1. **Who's the target?** — Pods labelled `app: postgres` (our database)
2. **Who's the source?** — Only pods labelled `app: backend` (our API)
3. **Which port?** — Only TCP port 5432 (PostgreSQL's port)

### NetworkPolicy Gotchas

**Network plugin requirement**: NetworkPolicies only work if your cluster's CNI (Container Network Interface) plugin supports them.

| CNI Plugin | Supports NetworkPolicy? |
|-----------|------------------------|
| Calico | Yes |
| Cilium | Yes |
| Weave Net | Yes |
| Flannel | No (by default) |
| minikube default | No — need to start with `--cni=calico` |

If your CNI doesn't support NetworkPolicies, the resource is silently ignored — no errors, no protection.

**Implicit deny**: Once you apply ANY NetworkPolicy that selects a pod, all traffic not explicitly allowed is **denied**. If you accidentally create a policy that allows nothing, you'll lock out all traffic to those pods.

**Namespace scope**: Our policy only affects pods in the `multi-tier-app` namespace. Pods in other namespaces are unaffected.

## Testing This Layer

### Testing Ingress

```bash
# Get the Ingress address
kubectl -n multi-tier-app get ingress

# For minikube:
minikube ip
# Open http://<minikube-ip> in your browser

# Or use curl:
curl http://<minikube-ip>/
curl http://<minikube-ip>/api/health
curl http://<minikube-ip>/api/data
```

### Testing NetworkPolicy

```bash
# Test that backend CAN connect to database:
kubectl -n multi-tier-app exec -it deploy/backend -- \
  python -c "import psycopg2; print(psycopg2.connect(host='postgres', dbname='multitierdb', user='postgres', password='securepassword123'))"
# Expected: Connection object (success)

# Test that frontend CANNOT connect to database:
# First, install netcat in a frontend pod temporarily:
kubectl -n multi-tier-app exec -it deploy/frontend -- \
  sh -c "apk add --no-cache netcat-openbsd && nc -zv postgres 5432 -w 3"
# Expected: Connection timed out (blocked by NetworkPolicy)
```

## Common Issues

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Ingress shows no ADDRESS | Ingress Controller not installed | `minikube addons enable ingress` |
| 404 on all paths | Wrong `pathType` or service name | Check service names match exactly |
| NetworkPolicy not blocking anything | CNI doesn't support it | Start minikube with `--cni=calico` |
| Backend can't reach database after applying policy | Label mismatch | Verify `app: backend` label on backend pods matches the policy's `from` selector |
