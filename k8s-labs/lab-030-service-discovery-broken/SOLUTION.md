# Lab 030 — Service Discovery Broken

## TLDR: What's Actually Going On (Plain English)

Imagine you're a postman trying to deliver letters to "the red house on Maple Street." But the address on your list says "the blue house on Oak Street." You walk around, find nothing matching, and give up. No delivery happens.

That's exactly what's broken here.

Kubernetes uses a **Service** to send traffic to your pods (your running app containers). But the Service doesn't find pods by name — it finds them by **labels** (little tags you stick on pods, like sticky notes saying `app: backend-api`).

In this lab, the Service's address book (its **selector**) is looking for pods tagged `app: backend` and `tier: api`. But the actual pods are tagged `app: backend-api` and `tier: backend`. No match — so the Service routes traffic to nobody, and every connection fails.

On top of that, even if the labels were fixed, the Service would still be sending traffic to the **wrong port** on the pod (port 8080 instead of port 80 where Nginx is actually listening).

**Two things to fix:**
1. The label selector — so the Service can find the pods
2. The target port — so traffic lands on the right door once it gets there

---

## The Problem

A Kubernetes Service called `backend-api` exists but has **no endpoints** — meaning it can't route traffic to any pods. The backend pods are running and healthy, but the Service doesn't know about them. When other pods try to reach `http://backend-api`, the connection is refused because the Service has no backends to forward traffic to.

There are **two issues** in the Service manifest:

1. **Label selector doesn't match pod labels** — the Service's selector says `app: backend` and `tier: api`, but the actual pods have labels `app: backend-api` and `tier: backend`. Since the selector doesn't match any pods, Kubernetes assigns zero endpoints to the Service.
2. **`targetPort` doesn't match the container port** — the Service says `targetPort: 8080`, but the Nginx containers inside the pods listen on port 80. Even if the selector matched, traffic would be forwarded to the wrong port and get "connection refused."

---

## Why Are There Two YAML Files?

When you list the manifests folder you'll see two files:

```
backend-deployment.yaml
backend-service.yaml
```

They're separate because they're two completely different Kubernetes objects with different jobs:

**`backend-deployment.yaml`** defines the **pods** — how many replicas to run, what container image to use, what ports the container listens on, and what labels to attach to the pods. It's the "here's what to run" instruction.

**`backend-service.yaml`** defines the **Service** — the stable network address that routes traffic to those pods. It's the "here's how to reach what's running" instruction.

They're kept separate because they have independent lifecycles. You might want to scale your Deployment without touching the Service, or update routing rules without redeploying your app. When you run `kubectl apply -f manifests/broken/`, Kubernetes reads both files and creates both objects in one go.

**In this lab, only `backend-service.yaml` needs to be fixed.** The Deployment is correct — the pods are running fine with the right labels and the right port. All the bugs are on the Service side.

---

## Thought Process

When a Kubernetes Service doesn't work, an experienced engineer checks the label-selector-endpoint chain:

1. **Check endpoints** — if the endpoints list is empty (`<none>`), the Service selector doesn't match any pods.
2. **Describe the Service** — `kubectl describe svc` gives you a human-readable view of the selector, ports, and endpoint state all in one place.
3. **Compare to pod labels** — `kubectl get pods --show-labels` shows what the pods are actually tagged with. Compare these to the selector — every key-value pair must match exactly.
4. **Confirm the correct port** — don't guess what port the container listens on. Check the Deployment manifest or `kubectl describe pod` to find the declared `containerPort`. That's your source of truth.
5. **Test from inside the cluster** — use a temporary pod with `curl` to verify end-to-end connectivity, because ClusterIP Services aren't reachable from outside the cluster.

The key concept: Kubernetes Services use **label selectors** to find pods. A Service with selector `app: X` only routes traffic to pods that have the label `app: X`. It's not about names — it's about matching labels exactly.

---

## Step-by-Step Solution

### Step 1: Apply the broken manifests

```bash
kubectl apply -f k8s-labs/lab-030-service-discovery-broken/manifests/broken/
```

| Part | What it does |
|------|-------------|
| `kubectl` | The Kubernetes command-line tool |
| `apply` | Create or update resources from a file (safe to re-run) |
| `-f k8s-labs/lab-030-service-discovery-broken/manifests/broken/` | Read all YAML files from this folder and apply them |

This creates the Deployment (2 replicas of the backend pod) and the broken Service. Run this from the `cloud-engineer-labs` root directory — if you're in a subdirectory the path won't resolve and you'll get `error: the path does not exist`.

---

### Step 2: Check the Service endpoints

```bash
kubectl get endpoints backend-api
```

| Part | What it does |
|------|-------------|
| `kubectl get` | List one or more resources |
| `endpoints` | The resource type — Kubernetes maintains an Endpoints object for each Service, listing the pod IPs it routes to |
| `backend-api` | The name of the specific Service (and its matching Endpoints object) to inspect |

You'll see `<none>` — the Service has no endpoints because its selector doesn't match any pods. This is the single most useful diagnostic when a Service isn't working. Start here, every time.

> **Note:** You may see a deprecation warning about `v1 Endpoints`. This is fine — the command still works and the concept is identical. Newer Kubernetes versions use EndpointSlices under the hood but the behaviour is the same.

---

### Step 3: Describe the Service and compare to pod labels

```bash
kubectl describe svc backend-api
kubectl get pods --show-labels
```

**Command 1 breakdown:**

| Part | What it does |
|------|-------------|
| `kubectl describe` | Show a detailed, human-readable summary of a resource — far more readable than raw YAML for diagnosis |
| `svc` | Shorthand for `service` |
| `backend-api` | The specific Service to inspect |

`describe` gives you everything in one view — the selector, the port mapping, the endpoints state, and any recent events. It's the most practical diagnostic command for Services and more useful day-to-day than wrestling with jsonpath output.

**What the output tells you:**

```
Selector:    app=backend,tier=api      ← Bug 1: wrong labels
TargetPort:  8080/TCP                  ← Bug 2: wrong port
Endpoints:   <none>                    ← Symptom: no pods matched
```

**Command 2 breakdown:**

| Part | What it does |
|------|-------------|
| `kubectl get pods` | List all pods in the current namespace |
| `--show-labels` | Add an extra column showing all labels attached to each pod |

This reveals the mismatch:
- Service selector wants: `app=backend, tier=api`
- Pods actually have: `app=backend-api, tier=backend`

---

### Step 4: Confirm the correct container port

You know `targetPort: 8080` is wrong from the `describe` output — but how do you know what the *correct* port should be? You don't guess. You check the Deployment manifest:

```bash
cat k8s-labs/lab-030-service-discovery-broken/manifests/broken/backend-deployment.yaml
```

Look for the `containerPort` field in the container spec. Whatever value is declared there is the port your application inside the container is actually listening on — and that's the value `targetPort` must match.

You can also find it via:

```bash
kubectl describe pod <pod-name>
```

Look for the `Port:` line in the Containers section. In this lab, both methods confirm the container listens on port `80`.

> **The Deployment manifest is always your source of truth for the correct port.** Never assume — always verify.

---

### Step 5: Fix the Service manifest

```bash
nano k8s-labs/lab-030-service-discovery-broken/manifests/broken/backend-service.yaml
```

Make the following changes:

**Before vs after:**

| Field | Broken | Fixed |
|-------|--------|-------|
| `selector.app` | `backend` | `backend-api` |
| `selector.tier` | `api` | `backend` |
| `targetPort` | `8080` | `80` |

The fixed file should look like this:

```yaml
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
```

| Field | What it does |
|-------|-------------|
| `selector.app: backend-api` | Now matches the actual pod label |
| `selector.tier: backend` | Now matches the actual pod label |
| `port: 80` | The port the Service listens on — what clients inside the cluster connect to |
| `targetPort: 80` | The port the Service forwards traffic to on each pod — must match `containerPort` |

---

### Step 6: Apply the fixed Service

```bash
kubectl apply -f k8s-labs/lab-030-service-discovery-broken/manifests/broken/backend-service.yaml
```

| Part | What it does |
|------|-------------|
| `kubectl apply` | Update an existing resource (or create it if it doesn't exist) |
| `-f ...backend-service.yaml` | Apply only this specific file — no need to reapply the whole folder |

You should see `service/backend-api configured` confirming the update was accepted. Kubernetes immediately re-evaluates which pods match the updated selector and refreshes the endpoints list.

> **Important:** Editing the YAML file on disk alone does nothing. The change only takes effect when Kubernetes receives it via `kubectl apply`. If endpoints are still empty after your edit, this is the most likely reason.

---

### Step 7: Verify endpoints are populated

```bash
kubectl get endpoints backend-api
```

Same command as Step 2. This time you should see **2 IP addresses** — one for each replica pod — for example:

```
NAME          ENDPOINTS                     AGE
backend-api   10.42.0.12:80,10.42.0.13:80   46m
```

If you still see `<none>`, the most likely cause is forgetting to reapply the file after editing it.

---

### Step 8: Test connectivity from inside the cluster

```bash
kubectl run curl-test --image=curlimages/curl --rm -i --restart=Never -- curl -s http://backend-api
```

| Part | What it does |
|------|-------------|
| `kubectl run curl-test` | Create a temporary pod named `curl-test` |
| `--image=curlimages/curl` | Use a minimal image with `curl` pre-installed |
| `--rm` | Automatically delete the pod when it exits — no cleanup needed |
| `-i` | Attach to the pod's output so you see the result in your terminal |
| `--restart=Never` | Run once and exit — don't keep restarting like a Deployment would |
| `--` | Separator: everything after this runs inside the container, not on your machine |
| `curl -s http://backend-api` | Make an HTTP request to the Service by its DNS name; `-s` suppresses the progress bar |

> **Why run this from inside the cluster?** ClusterIP Services have an internal-only IP address — they are deliberately not reachable from your laptop or anywhere outside the cluster. This temporary pod gives you that inside perspective to test from.

> **You don't need to memorise this command.** In a real job it'd be in a runbook or a quick search away. What matters is understanding *why* you're doing it.

You should see the Nginx welcome page, proving end-to-end connectivity through the Service. Kubernetes DNS automatically resolves `backend-api` to the Service's cluster IP within the same namespace.

---

### Step 9: Run the validator

```bash
./tools/labrunner.sh validate k8s-labs/lab-030-service-discovery-broken
```

All four checks should pass:

```
✅  backend-api service has endpoints
✅  Service has 2+ endpoints (matching replicas)
✅  Service targetPort matches container port (80)
✅  Can curl backend-api service from within cluster
```

---

## Reading `kubectl describe svc` Output

This is one of your most powerful diagnostic tools. Here's what every line means, using the actual output from this lab:

```
Name:              backend-api        ← The Service object name
Namespace:         default            ← The namespace it lives in ("default" if none specified)
Labels:            <none>             ← Labels on the Service itself — used to organise Services, not to find pods
Annotations:       <none>             ← Extra metadata for tools like monitoring or ingress controllers
Selector:          app=backend,tier=api  ← ⚠️ BUG 1: doesn't match pod labels
Type:              ClusterIP          ← Internal-only — not reachable from outside the cluster
IP:                10.43.221.80       ← The stable internal IP Kubernetes assigned — never changes even as pods restart
Port:              <unset>  80/TCP    ← The port clients connect to on the Service
TargetPort:        8080/TCP           ← ⚠️ BUG 2: wrong port — container listens on 80, not 8080
Endpoints:         <none>             ← ⚠️ SYMPTOM: selector matched zero pods
Session Affinity:  None               ← Each request can go to any matching pod — no sticky sessions
Events:            <none>             ← No recent errors logged against this Service
```

---

## Real-World Context

- **Service types:** This lab uses the default type (`ClusterIP`) — only reachable from inside the cluster. In production you'd also encounter `NodePort` (accessible on each node's IP), `LoadBalancer` (provisions a cloud load balancer — common in AWS/EKS), and `ExternalName` (DNS alias for external services).
- **Label conventions:** Production clusters often use Kubernetes recommended labels like `app.kubernetes.io/name` and `app.kubernetes.io/component` — a standardised naming scheme that prevents the exact label mismatches seen here.
- **Tandem Bank parallel:** In your AWS/EKS environment, this same label-selector mechanism is what connects Services to pods. When a deployment rolls out and traffic stops flowing, checking endpoints is one of the first things an on-call engineer does.
- **DNS resolution:** Inside a Kubernetes cluster, Services are reachable by their short name (`backend-api`) within the same namespace, or by their full DNS name (`backend-api.default.svc.cluster.local`) from any namespace. CoreDNS provides this resolution automatically.
- **EndpointSlices:** In modern Kubernetes (1.21+), EndpointSlices replace the older Endpoints resource for better scalability. The deprecation warning you'll see when running `kubectl get endpoints` is referring to this change — the concept is identical.

---

## Key Concepts

- **Services find pods by labels, not by name** — the Service name and the pod name are completely unrelated. What connects them is the `selector` matching the pod's `metadata.labels`.
- **`kubectl get endpoints` is the primary diagnostic** — empty endpoints = selector mismatch. Start here every time a Service isn't working.
- **`kubectl describe svc` is your best all-in-one view** — selector, ports, and endpoint state in one readable output. More practical than jsonpath for day-to-day diagnosis.
- **Don't guess the correct port — look it up** — check `containerPort` in the Deployment manifest or via `kubectl describe pod`. The Deployment is the source of truth.
- **All selector labels must match exactly** — if the selector has two labels, both must be present on the pod with exactly matching values. Partial matches don't count.
- **Labels are case-sensitive** — `app: Backend` and `app: backend` are different labels.
- **Editing a file does nothing until you reapply** — always follow a file edit with `kubectl apply`.

---

## Common Mistakes

- **Fixing only the selector OR only the port** — both issues must be fixed. A correct selector with a wrong `targetPort` means the Service finds pods but traffic still gets "connection refused" at the pod.
- **Running `kubectl apply` from the wrong directory** — if the path doesn't resolve you'll get `error: the path does not exist`. Always run from the repo root or use the full relative path.
- **Editing the file but forgetting to reapply** — the change only takes effect when Kubernetes receives it via `kubectl apply`. This is the most common reason endpoints are still empty after a fix.
- **Guessing the correct `targetPort`** — always verify against the Deployment manifest or `kubectl describe pod`. Don't assume.
- **Confusing `port` and `targetPort`** — `port` is what clients connect to on the Service. `targetPort` is where the Service forwards traffic on each pod. They can differ, but `targetPort` must match `containerPort`.
- **Testing from outside the cluster** — `ClusterIP` Services are not reachable from your laptop. Use a temporary in-cluster pod (as in Step 8) or `kubectl port-forward` to test them.
