# Solution Walkthrough — Ingress Misconfigured

## The Problem

A Kubernetes Ingress resource is supposed to route external traffic to the application's frontend and API services, but all requests return 404 errors. The Ingress exists, the backend services are healthy, and the Ingress controller is running — but the routing rules are wrong. There are **two issues** in the Ingress manifest:

1. **Root path references wrong service name** — the Ingress routes the `/` path to `web-frontend`, but the actual Service is called `frontend`. Since no Service named `web-frontend` exists, the Ingress controller can't find a backend for root path requests and returns 404.
2. **Wrong port numbers** — the root path uses port `8080` and the API path uses port `3000`, but both Services actually listen on port `80`. The Ingress forwards traffic to the wrong port, resulting in connection failures.

## Thought Process

When an Ingress returns 404 for all paths, an experienced Kubernetes engineer checks:

1. **Do the backend Services exist?** `kubectl get svc` lists all Services. Compare the names with what the Ingress references.
2. **Do the Services have endpoints?** `kubectl get endpoints` confirms the Services have pods backing them.
3. **Does the Ingress reference the correct names and ports?** `kubectl get ingress app-ingress -o yaml` shows the routing rules. Cross-reference every service name and port number against the actual Service definitions.
4. **Is the Ingress controller running?** `kubectl get pods -n ingress-nginx` (or whichever namespace the controller uses) confirms the controller is up and processing Ingress resources.

The key insight: an Ingress is just a set of routing rules. The Ingress controller (Nginx, Traefik, etc.) reads these rules and configures its own routing accordingly. If a rule references a non-existent Service or wrong port, the controller either returns 404 or a 502 Bad Gateway.

## Step-by-Step Solution

### Step 1: Apply the broken manifests (if not already applied)

```bash
kubectl apply -f manifests/broken/
```

**What this does:** Creates the Services and the broken Ingress resource.

### Step 2: Check the current Ingress configuration

```bash
kubectl get ingress app-ingress -o yaml
```

**What this does:** Shows the full Ingress resource definition including the routing rules. Look at each path entry — which service name and port does it reference?

### Step 3: List the actual Services

```bash
kubectl get svc
```

**What this does:** Shows all Services in the current namespace. You'll see `frontend` (port 80) and `api-service` (port 80). Notice: there's no `web-frontend` — but the Ingress references that name.

### Step 4: Compare Ingress rules vs actual Services

Looking at the broken Ingress:
- Path `/` → `web-frontend:8080` — but the Service is called `frontend` and listens on port `80`
- Path `/api` → `api-service:3000` — the name `api-service` is correct, but the port should be `80`, not `3000`

### Step 5: Fix the Ingress manifest

```bash
cat > manifests/broken/ingress.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend
            port:
              number: 80
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 80
EOF
```

**What this does:** Fixes both issues:

1. **`name: frontend`** (was `web-frontend`) — now references the actual Service name. The Ingress controller can find this Service and route traffic to it.
2. **`port: number: 80`** for both paths (were `8080` and `3000`) — matches the actual Service port. The Ingress forwards traffic to port 80 on each Service, which then forwards to the pods' target ports.

The rest of the Ingress remains the same:
- `host: app.example.com` — the domain name for routing
- `pathType: Prefix` — matches any path that starts with the specified prefix
- `rewrite-target: /` — rewrites the URL path before forwarding (so `/api/users` becomes `/users` when it reaches the API service)

### Step 6: Apply the fixed Ingress

```bash
kubectl apply -f manifests/broken/ingress.yaml
```

**What this does:** Updates the Ingress resource. The Ingress controller detects the change and reconfigures its routing table.

### Step 7: Verify the Ingress configuration

```bash
kubectl describe ingress app-ingress
```

**What this does:** Shows the Ingress details including the routing rules and whether the backends are resolved. You should see both paths with their correct Service names and ports, and no error warnings about missing backends.

### Step 8: Verify the routing rules

```bash
kubectl get ingress app-ingress -o jsonpath='{range .spec.rules[0].http.paths[*]}{.path} -> {.backend.service.name}:{.backend.service.port.number}{"\n"}{end}'
```

**What this does:** Extracts and displays the routing rules in a human-readable format. You should see:
- `/ -> frontend:80`
- `/api -> api-service:80`

## Docker Lab vs Real Life

- **Ingress controllers:** This lab assumes an Nginx Ingress controller. In production, you might use AWS ALB Ingress Controller, Traefik, HAProxy, Istio Gateway, or others. Each has slightly different annotations and features.
- **TLS/HTTPS:** Production Ingresses include TLS configuration with a certificate Secret. You'd add a `tls:` section referencing a Secret containing the certificate and key. Let's Encrypt with cert-manager can automate certificate provisioning.
- **Multiple hosts:** Production Ingresses often route to different services based on hostname (virtual hosting). You'd have multiple `host:` entries for `app.example.com`, `api.example.com`, etc.
- **Path matching:** `pathType: Prefix` matches any path starting with the prefix. `pathType: Exact` matches only the exact path. In production, you'd use Exact for specific endpoints and Prefix for general routing.
- **Gateway API:** The newer Kubernetes Gateway API is gradually replacing Ingress for more complex routing needs. It provides more expressive routing rules, but Ingress remains widely used for simpler configurations.
- **Testing locally:** To test an Ingress with a custom hostname locally, you'd add `app.example.com` to your `/etc/hosts` file pointing to the Ingress controller's IP, or use `curl -H "Host: app.example.com" http://<ingress-ip>/`.

## Key Concepts Learned

- **Ingress service names must match actual Service names exactly** — the Ingress controller looks up Services by name. A wrong name means no backend, which means 404 errors.
- **The port in the Ingress must match the Service's `port`** — this is the Service's listening port (not the pod's containerPort). The Service handles mapping from its port to the pod's targetPort.
- **`kubectl describe ingress` is the key diagnostic** — it shows the routing rules and warns about missing backends
- **Ingress is just routing rules; the controller does the work** — the Ingress resource is a declaration of what you want. The Ingress controller (a pod running Nginx, Traefik, etc.) reads it and configures the actual routing.
- **`kubectl get svc` is your cross-reference** — always compare the Ingress's service references against the actual Services that exist in the cluster

## Common Mistakes

- **Using the pod name or Deployment name instead of the Service name** — the Ingress routes to Services, not directly to pods or Deployments. The Service name is what matters.
- **Confusing Service port with container port** — the Ingress references the Service's `port`, not the pod's `containerPort`. The Service maps between the two. If the Service has `port: 80, targetPort: 3000`, the Ingress should use port 80.
- **Not checking if the Ingress controller is installed** — an Ingress resource does nothing without an Ingress controller running in the cluster. On managed Kubernetes (EKS, GKE, AKS), you may need to install one separately.
- **Forgetting the `rewrite-target` annotation** — without it, a request to `/api/users` is forwarded to the API service as `/api/users`. With `rewrite-target: /`, it's rewritten to `/users`. Whether you need this depends on your application's routing.
- **Host-based routing with wrong DNS** — if the Ingress specifies `host: app.example.com`, requests without that Host header (or with a different hostname) won't match the rule. During testing, use `curl -H "Host: app.example.com"` to simulate the correct hostname.
