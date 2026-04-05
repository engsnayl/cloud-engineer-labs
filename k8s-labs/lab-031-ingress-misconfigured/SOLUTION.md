# Solution Walkthrough — Lab 031: Ingress Misconfigured

---

## TLDR

The Ingress resource (the "front door" that routes external web traffic into the cluster) has two routing rules, and both are broken. The root path `/` points to a service called `web-frontend`, but the actual service is called `frontend` — wrong name means the Ingress controller can't find anything to send traffic to, so it returns a 404. On top of that, both routing rules specify the wrong port numbers (8080 and 3000 instead of 80). Fix the service name and both port numbers in the Ingress manifest, reapply it, and traffic routes correctly.

---

## The Problem

A Kubernetes Ingress resource is supposed to route external traffic to the application's frontend and API services, but all requests return 404 errors. The Ingress exists, the backend services are healthy, and the Ingress controller is running — but the routing rules are wrong. There are **two issues** in the Ingress manifest:

1. **Root path references wrong service name** — the Ingress routes the `/` path to `web-frontend`, but the actual Service is called `frontend`.
2. **Wrong port numbers** — the root path uses port `8080` and the API path uses port `3000`, but both Services actually listen on port `80`.

---

## Step-by-Step Investigative Learning Pathway

This section walks through the diagnosis the way an engineer would approach it in real time — starting from "something is broken" and working logically toward the fix.

### Step 1: Understand what you're working with

Before touching anything, you need to know what the Ingress is currently configured to do. Think of the Ingress as a routing table — it says "when traffic arrives at this URL path, send it to this service on this port." Your first job is to read that routing table.

```bash
kubectl get ingress app-ingress -o yaml
```

**Command breakdown:**

| Part | What it does |
|------|-------------|
| `kubectl` | The Kubernetes command-line tool — talks to the cluster's API server |
| `get` | Retrieve a resource from the cluster |
| `ingress` | The type of resource you're looking up |
| `app-ingress` | The specific name of the Ingress resource |
| `-o yaml` | Output the full definition in YAML format (shows everything, not just the summary) |

**What to look for:** In the output, find the `spec.rules` section. This contains the routing rules. Each rule has a `path` (the URL path to match), a `service.name` (where to send traffic), and a `service.port.number` (which port to forward to).

You'll see:
- Path `/` → `web-frontend:8080`
- Path `/api` → `api-service:3000`

At this point you don't yet know if these are correct. You need to cross-reference against reality.

### Step 2: What services actually exist in the cluster?

The Ingress says it wants to send traffic to `web-frontend` and `api-service`. Do those services actually exist? And if they do, what ports do they listen on?

```bash
kubectl get svc
```

**Command breakdown:**

| Part | What it does |
|------|-------------|
| `kubectl` | The Kubernetes command-line tool |
| `get` | Retrieve resources from the cluster |
| `svc` | Short for "services" — lists all Service resources in the current namespace |

**What to look for:** The output shows every Service's name, type, cluster IP, and port. Compare these names and ports against what the Ingress expects.

You'll see:
```
NAME          TYPE        CLUSTER-IP     EXTERNAL-IP   PORT(S)   AGE
api-service   ClusterIP   10.43.37.52    <none>        80/TCP    13m
frontend      ClusterIP   10.43.97.221   <none>        80/TCP    13m
kubernetes    ClusterIP   10.43.0.1      <none>        443/TCP   24d
```

### Step 3: Compare — what mismatches can you spot?

Now you have both sides of the picture. Line them up:

| Path | Ingress expects | What actually exists | Problem |
|------|----------------|---------------------|---------|
| `/` | `web-frontend:8080` | Service is called `frontend`, port `80` | Wrong name AND wrong port |
| `/api` | `api-service:3000` | Service is called `api-service`, port `80` | Name is correct, but wrong port |

Two mismatches on the root path (name and port), one mismatch on the API path (port only). The Ingress controller can't route traffic to a service that doesn't exist (`web-frontend`), and even where the name is right (`api-service`), it's sending traffic to the wrong port.

### Step 4: Where do I make the fix?

You've identified the problem. Now — where do you go to fix it? You have two options:

- **Option A: `kubectl edit ingress app-ingress`** — opens the live resource in your editor. Quick for one-off fixes, but the change only exists in the cluster, not in your files.
- **Option B: Fix the manifest file and reapply** — better for labs and production, because you end up with a corrected file that's version-controlled and repeatable.

Since the lab has manifest files in `manifests/broken/`, Option B is the right approach. Look at the file:

```bash
cat manifests/broken/ingress.yaml
```

### Step 5: Fix the Ingress manifest

Open the file in `vi`:

```bash
vi manifests/broken/ingress.yaml
```

Make two changes:

1. **Change `web-frontend` to `frontend`** — under the `/` path's backend service name
2. **Change both port numbers to `80`** — `8080` becomes `80` under the `/` path, and `3000` becomes `80` under the `/api` path

The corrected routing rules section should look like this:

**Before (broken):**
```yaml
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-frontend
            port:
              number: 8080
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 3000
```

**After (fixed):**
```yaml
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
```

### Step 6: Apply the fix

```bash
kubectl apply -f manifests/broken/ingress.yaml
```

**Command breakdown:**

| Part | What it does |
|------|-------------|
| `kubectl apply` | Sends the resource definition to the Kubernetes API server. If the resource already exists, it updates it; if it doesn't exist, it creates it |
| `-f ingress.yaml` | Specifies the file to read the resource definition from |

**Important:** Make sure you run this from the directory where the file lives, or provide the full path. If you're already in `manifests/broken/`, then `-f ingress.yaml` is enough. If you're in the repo root, you'd need `-f k8s-labs/lab-031-ingress-misconfigured/manifests/broken/ingress.yaml`.

You should see: `ingress.networking.k8s.io/app-ingress configured`

### Step 7: Verify the fix

```bash
kubectl describe ingress app-ingress
```

**Command breakdown:**

| Part | What it does |
|------|-------------|
| `kubectl describe` | Shows detailed information about a resource, including events, status, and configuration — more human-readable than `-o yaml` |
| `ingress` | The resource type |
| `app-ingress` | The specific resource name |

**What to look for:** Under `Rules`, you should now see:
```
  Host             Path  Backends
  ----             ----  --------
  app.example.com
                   /      frontend:80
                   /api   api-service:80
```

Both paths now point to the correct service names on the correct port. No warnings about missing backends.

### Step 8: Run validation

```bash
lab validate
```

---

## Kubernetes Architecture — How Ingress Fits In

Understanding where Ingress sits in the Kubernetes stack helps make sense of this lab. Think of it in layers, from the outside in:

**Cluster** — the whole system. A group of machines managed as one unit. Your Pi is a single-node cluster (one machine playing every role).

**Nodes** — individual machines in the cluster. Control plane nodes run the management components (API server, scheduler, etcd database). Worker nodes run your actual application containers. On your Pi with K3s, one machine does both.

**Pods** — the smallest deployable unit. One or more containers running together on a node. When you deploy your `frontend` app, Kubernetes creates pods and decides which node to run them on.

**Services** — a stable abstraction in front of pods. Pods can die and restart with new IPs. A Service gives you a fixed name and IP that always routes to whatever pods are currently healthy. `frontend` at `10.43.97.221` always finds the frontend pods, even if the actual pods have been replaced.

**Ingress** — the "front door" sitting in front of Services. It takes external traffic entering the cluster and routes it to the right Service based on URL path or hostname. But the Ingress resource itself is just a declaration — it does nothing on its own. An **Ingress controller** (a running pod — Traefik on K3s, Nginx on many other setups) reads these declarations and configures the actual routing.

**The request flow:**
```
Internet → Ingress Controller (Traefik pod) → reads Ingress rules → routes to correct Service → Service forwards to healthy Pod → container handles the request
```

---

## Docker Lab vs Real Life

- **Ingress controllers:** This lab uses Traefik (K3s default). In production, you might use Nginx Ingress Controller, AWS ALB Ingress Controller, HAProxy, or Istio Gateway. Each has different annotations and capabilities.
- **TLS/HTTPS:** Production Ingresses include TLS configuration with certificate Secrets. Let's Encrypt with cert-manager can automate certificate provisioning.
- **Multiple hosts:** Production Ingresses often route to different services based on hostname (virtual hosting) — separate `host:` entries for `app.example.com`, `api.example.com`, etc.
- **Path matching:** `pathType: Prefix` matches any path starting with the prefix. `pathType: Exact` matches only the exact path. Production uses both depending on the routing need.
- **Gateway API:** The newer Kubernetes Gateway API is gradually replacing Ingress for complex routing. It provides more expressive rules, but Ingress remains widely used for simpler setups.
- **Testing locally:** To test an Ingress with a custom hostname locally, add `app.example.com` to your `/etc/hosts` file pointing to the Ingress controller's IP, or use `curl -H "Host: app.example.com" http://<ingress-ip>/`.

---

## Key Concepts

- **Ingress service names must match actual Service names exactly** — the Ingress controller looks up Services by name. A wrong name means no backend, which means 404.
- **The port in the Ingress must match the Service's `port`** — this is the Service's listening port, not the pod's containerPort. The Service handles the mapping from its port to the pod's targetPort.
- **`kubectl describe ingress` is the key diagnostic command** — it shows routing rules and warns about missing backends.
- **Ingress is just routing rules; the controller does the work** — the Ingress resource is a declaration. The Ingress controller (Traefik, Nginx, etc.) reads it and does the actual routing.
- **`kubectl get svc` is your cross-reference** — always compare the Ingress's service references against the Services that actually exist.
- **`kubectl get ingress` follows the same pattern as every other kubectl command** — it's not a special command. `kubectl get <resource-type>` works for pods, services, deployments, ingresses, configmaps, secrets, and every other Kubernetes resource.

---

## Common Mistakes

- **Using the pod name or Deployment name instead of the Service name** — the Ingress routes to Services, not directly to pods or Deployments.
- **Confusing Service port with container port** — the Ingress references the Service's `port`, not the pod's `containerPort`. If the Service has `port: 80, targetPort: 3000`, the Ingress should use port `80`.
- **Not checking if the Ingress controller is installed** — an Ingress resource does nothing without a controller. On managed Kubernetes (EKS, GKE, AKS), you may need to install one separately.
- **Forgetting the `rewrite-target` annotation** — without it, `/api/users` is forwarded as `/api/users`. With `rewrite-target: /`, it becomes `/users`. Whether you need this depends on the application.
- **Running `kubectl apply -f` with the wrong path** — if you're already inside the directory containing the file, use just the filename. If you provide a path relative to a different directory, kubectl won't find it.

---

## Cleanup / Reset

To reset this lab back to its starting state so you can run it again from scratch:

```bash
# Delete the Ingress and Services from the cluster
kubectl delete ingress app-ingress
kubectl delete -f ~/cloud-engineer-labs/k8s-labs/lab-031-ingress-misconfigured/manifests/broken/services.yaml

# Restore the broken Ingress manifest (undo your fixes)
cd ~/cloud-engineer-labs
git checkout -- k8s-labs/lab-031-ingress-misconfigured/manifests/broken/ingress.yaml
```

**Command breakdown:**

| Command | What it does |
|---------|-------------|
| `kubectl delete ingress app-ingress` | Removes the Ingress resource from the cluster by name |
| `kubectl delete -f services.yaml` | Removes the resources defined in the services file from the cluster |
| `git checkout -- <file>` | Restores a file to its last committed state in Git — undoes any local changes you made. The `--` separates the git command from the file path |

After running these commands, the cluster has no lab resources and the broken manifest is restored. You can start the lab fresh with `lab start` followed by `kubectl apply -f manifests/broken/`.

---

## Pi / K3s Environment Notes

- K3s ships with **Traefik** as its default Ingress controller, not Nginx. You'll notice `ingressClassName: traefik` in the Ingress output. The diagnostic and fix process is identical regardless of which controller is used — the Ingress resource spec is the same.
- The Ingress controller runs in the `kube-system` namespace. You can confirm it's running with `kubectl get pods -n kube-system | grep traefik`.
- The `~/.kube/config` file on your Pi is what allows `kubectl` to communicate with the K3s cluster. K3s sets this up automatically at install time.
