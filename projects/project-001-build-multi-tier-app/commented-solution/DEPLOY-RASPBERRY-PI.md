# Deploying on Your Raspberry Pi 5

A step-by-step guide to getting the multi-tier app running on your Pi.
Written for your exact setup:

| Detail | Your Setup |
|--------|-----------|
| **Hardware** | Raspberry Pi 5 Model B, 4GB RAM |
| **OS** | Debian 12 (Bookworm), aarch64 |
| **Docker** | v29.2.1 (already installed) |
| **k3s** | v1.34.4 (already installed) |
| **Disk** | ~91GB free |

---

## Before You Start: How This All Fits Together

Here's what's about to happen at a high level:

```
 Your Pi
 ┌──────────────────────────────────────────────────────┐
 │  k3s (lightweight Kubernetes)                        │
 │  ┌────────────────────────────────────────────────┐  │
 │  │  Namespace: multi-tier-app                     │  │
 │  │                                                │  │
 │  │  ┌──────────┐  ┌──────────┐  ┌─────────────┐  │  │
 │  │  │ Frontend │  │ Backend  │  │ PostgreSQL  │  │  │
 │  │  │  nginx   │  │  Flask   │  │ StatefulSet │  │  │
 │  │  │ x2 pods  │  │ x2 pods  │  │  x1 pod     │  │  │
 │  │  └──────────┘  └──────────┘  └─────────────┘  │  │
 │  │                                                │  │
 │  │  Traefik Ingress (built into k3s)              │  │
 │  └────────────────────────────────────────────────┘  │
 │                                                      │
 │  Docker (used to BUILD the container images)         │
 └──────────────────────────────────────────────────────┘
         │
         │ http://<your-pi-ip>
         ▼
    Your browser (laptop/phone on same network)
```

**Two important things about YOUR setup:**

1. **k3s uses Traefik** (not nginx) as its Ingress Controller. Traefik comes
   pre-installed with k3s, so we don't need to install anything extra. We'll
   make a small tweak to the Ingress manifest to use Traefik instead of nginx.

2. **k3s uses containerd** (not Docker) to run containers. Even though Docker
   is installed, k3s has its own container runtime. So after building images
   with Docker, we need to **import** them into k3s. This is a simple
   `docker save | k3s ctr images import` pipeline — we'll walk through it.

---

## Step 0: Verify k3s Is Running

Before anything else, let's make sure k3s is healthy and you can talk to it.

```bash
# Check that the k3s service is active.
# You should see "active (running)" in green.
sudo systemctl status k3s
```

```bash
# Check that kubectl can talk to the cluster.
# "kubectl" is the command-line tool for Kubernetes — it sends commands to
# your cluster. k3s bundles its own copy.
# You should see one node (your Pi) with status "Ready".
sudo k3s kubectl get nodes
```

**Expected output:**
```
NAME        STATUS   ROLES                  AGE   VERSION
your-pi     Ready    control-plane,master   ...   v1.34.4+k3s1
```

If you see "Ready", you're good. If not, try `sudo systemctl restart k3s`.

### Make kubectl easier to use

By default, you need `sudo k3s kubectl` for everything. Let's fix that:

```bash
# Create a directory for kube config if it doesn't exist.
mkdir -p ~/.kube

# Copy the k3s config so regular kubectl can use it.
# The kubeconfig file contains the address of your cluster and credentials
# to authenticate — it's how kubectl knows where to send commands.
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config

# Make it owned by your user (not root), so you don't need sudo.
sudo chown $(id -u):$(id -g) ~/.kube/config

# Set the KUBECONFIG environment variable so kubectl finds the config.
# We also add it to .bashrc so it persists across terminal sessions.
export KUBECONFIG=~/.kube/config
echo 'export KUBECONFIG=~/.kube/config' >> ~/.bashrc
```

Now test without sudo:

```bash
kubectl get nodes
```

If that works, you can use just `kubectl` from now on (no more `sudo k3s kubectl`).

---

## Step 1: Get the Code Onto Your Pi

You need the solution files on your Pi. The easiest way is to clone the repo:

```bash
# Navigate to your home directory (or wherever you like to keep projects).
cd ~

# Clone the repository.
# "git clone" downloads a full copy of the repo to your Pi.
git clone https://github.com/engsnayl/cloud-engineer-labs.git

# Navigate into the project's commented solution.
cd cloud-engineer-labs/projects/project-001-build-multi-tier-app/commented-solution
```

Verify you can see the files:

```bash
# "ls" lists directory contents. You should see docker/, k8s/, README.md, etc.
ls -la
```

---

## Step 2: Build the Container Images

We use Docker to build the images, then import them into k3s.

### Build the backend image

```bash
# "docker build" reads the Dockerfile and creates a container image.
#   -t multi-tier-backend:latest    = Tag (name) the image
#   docker/backend/                 = Path to the directory containing the Dockerfile
#
# This will download the python:3.11-slim base image (ARM64 version
# is pulled automatically because your Pi is aarch64), install the
# Python packages, and copy your app.py into the image.
docker build -t multi-tier-backend:latest docker/backend/
```

This might take 2-3 minutes the first time (downloading base images + compiling
psycopg2). Subsequent builds are faster thanks to layer caching.

### Build the frontend image

```bash
# Much faster — nginx is tiny and we're just copying two files in.
docker build -t multi-tier-frontend:latest docker/frontend/
```

### Verify both images exist

```bash
# List images filtered by our names.
# "grep" filters the output to only show lines matching our search term.
docker images | grep multi-tier
```

**Expected output:**
```
multi-tier-backend    latest   abc123def456   1 minute ago    185MB
multi-tier-frontend   latest   789ghi012jkl   30 seconds ago  43MB
```

### Import images into k3s

k3s runs its own container runtime (containerd), separate from Docker.
The images we just built live in Docker's storage — k3s can't see them.
We need to export from Docker and import into k3s:

```bash
# "docker save" exports an image as a tar archive (a single file containing
# all the image layers). The pipe (|) sends that output directly to
# "k3s ctr images import" which loads it into k3s's containerd storage.
#
# The "-" at the end means "read from standard input" (i.e., from the pipe).
docker save multi-tier-backend:latest | sudo k3s ctr images import -
docker save multi-tier-frontend:latest | sudo k3s ctr images import -
```

### Verify k3s can see the images

```bash
# List images in k3s's containerd. Filter for ours.
sudo k3s ctr images list | grep multi-tier
```

You should see both `docker.io/library/multi-tier-backend:latest` and
`docker.io/library/multi-tier-frontend:latest`.

---

## Step 3: Deploy the Database Layer

We deploy bottom-up: database first, because the backend depends on it.

```bash
# Apply the namespace first — this creates the "room" everything lives in.
# "kubectl apply -f" reads a YAML file and creates/updates the resource.
kubectl apply -f k8s/namespace.yaml
```

```bash
# Deploy the Secret (database credentials), the init script ConfigMap,
# the StatefulSet (the actual database), and the Service (DNS name).
# Order matters: the Secret and ConfigMap must exist before the StatefulSet
# tries to reference them.
kubectl apply -f k8s/postgres-secret.yaml
kubectl apply -f k8s/postgres-init-configmap.yaml
kubectl apply -f k8s/postgres-statefulset.yaml
kubectl apply -f k8s/postgres-service.yaml
```

### Wait for the database to be ready

```bash
# "kubectl wait" blocks until a condition is met.
# We're waiting for the postgres-0 pod to be "Ready" (health checks passing).
# --timeout=120s means give up after 2 minutes if it's still not ready.
kubectl -n multi-tier-app wait --for=condition=Ready pod/postgres-0 --timeout=120s
```

**Expected output:** `pod/postgres-0 condition met`

### Verify it's working

```bash
# Check the pod status. You should see 1/1 READY and STATUS "Running".
kubectl -n multi-tier-app get pods -l app=postgres
```

```bash
# Check the logs to confirm PostgreSQL started and the init script ran.
# You should see messages about creating the "items" table and inserting data.
kubectl -n multi-tier-app logs postgres-0 | tail -20
```

### Optional: peek inside the database

```bash
# "kubectl exec" runs a command inside a running pod — like SSH but for containers.
# "-it" makes it interactive (so you get a prompt).
# "-- psql -U postgres -d multitierdb" is the command to run: start the
# PostgreSQL client, connect as user "postgres" to database "multitierdb".
kubectl -n multi-tier-app exec -it postgres-0 -- psql -U postgres -d multitierdb
```

Inside the psql prompt, try:

```sql
-- List all tables (should show "items")
\dt

-- See the seed data
SELECT * FROM items;

-- Exit psql
\q
```

---

## Step 4: Deploy the Backend Layer

```bash
# Deploy the ConfigMap (connection settings), Deployment (pods), and Service.
kubectl apply -f k8s/backend-configmap.yaml
kubectl apply -f k8s/backend-deployment.yaml
kubectl apply -f k8s/backend-service.yaml
```

### Wait for backend pods to be ready

```bash
# "rollout status" watches a Deployment and waits until all pods are ready.
# This is the Deployment equivalent of the "kubectl wait" we used for the database.
kubectl -n multi-tier-app rollout status deployment/backend --timeout=120s
```

### Test the backend directly

```bash
# "port-forward" creates a temporary tunnel from your Pi's localhost to a Service
# inside the cluster. This lets you test the backend without Ingress.
# The "&" at the end runs it in the background so you get your prompt back.
kubectl -n multi-tier-app port-forward svc/backend 5000:5000 &

# Give it a second to establish the tunnel.
sleep 2

# Hit the health endpoint.
# "curl" makes an HTTP request from the command line.
# You should see: {"database":"connected","status":"healthy"}
curl http://localhost:5000/api/health

# Hit the data endpoint.
# You should see the 3 seed items from the init script.
curl http://localhost:5000/api/data

# Stop the port-forward (bring it to foreground and kill it).
# "fg" brings the background process to the foreground, then Ctrl+C stops it.
# Or just kill it by process ID:
kill %1
```

---

## Step 5: Deploy the Frontend Layer

```bash
kubectl apply -f k8s/frontend-deployment.yaml
kubectl apply -f k8s/frontend-service.yaml

# Wait for frontend pods to be ready.
kubectl -n multi-tier-app rollout status deployment/frontend --timeout=120s
```

---

## Step 6: Deploy Networking (Ingress)

**Important note about k3s:** Your k3s installation comes with **Traefik** as
the Ingress Controller (not nginx). The Ingress manifest in our solution
references the nginx ingress class, so we need to tweak it slightly.

Run this command to create a Traefik-compatible version:

```bash
# "sed" is a stream editor — it finds and replaces text.
# We're replacing the nginx-specific annotations with Traefik's ingress class.
# The result is written to a new file so we don't modify the original.
#
# What changes:
#   - Removes the nginx.ingress.kubernetes.io/rewrite-target annotation
#     (Traefik handles path routing differently — it doesn't need this)
#   - Changes kubernetes.io/ingress.class from "nginx" to "traefik"
sed \
  -e '/nginx.ingress.kubernetes.io\/rewrite-target/d' \
  -e 's/kubernetes.io\/ingress.class: nginx/kubernetes.io\/ingress.class: traefik/' \
  k8s/ingress.yaml > k8s/ingress-traefik.yaml
```

Now apply it:

```bash
kubectl apply -f k8s/ingress-traefik.yaml
```

### Apply the NetworkPolicy

```bash
kubectl apply -f k8s/network-policy.yaml
```

> **Note:** k3s uses Flannel as its default network plugin, which does NOT
> enforce NetworkPolicies. The resource will be created without errors, but
> the firewall rules won't actually be enforced. This is fine for learning —
> the manifest is still correct and would work on a cluster with Calico or
> Cilium. If you want to explore this later, you can reinstall k3s with
> `--flannel-backend=none` and install Calico, but that's an advanced topic.

---

## Step 7: Access the App!

### Find your Pi's IP address

```bash
# "hostname -I" prints all IP addresses assigned to your Pi.
# The first one is typically your local network IP (e.g., 192.168.1.xxx).
hostname -I
```

### Open it in your browser

On **any device on the same network** (your laptop, phone, tablet), open:

```
http://<your-pi-ip>
```

For example: `http://192.168.1.42`

You should see the Multi-Tier Kubernetes Application page with:
- A "Backend: Healthy" / "Database: connected" status badge
- The three seed items from the database
- A form to add new items

### Test the API directly from the Pi

```bash
# Fetch the homepage
curl http://localhost

# Check backend health through the Ingress
curl http://localhost/api/health

# Get items from the database through the full stack
curl http://localhost/api/data

# Add a new item through the full stack
curl -X POST http://localhost/api/data \
  -H "Content-Type: application/json" \
  -d '{"name": "Raspberry Pi 5", "description": "My first K8s deployment!"}'

# Verify it was saved
curl http://localhost/api/data
```

---

## Step 8: Explore!

You've got a live Kubernetes application. Here are things to try:

### See everything that's running

```bash
# Show ALL resources in our namespace.
# This is the "bird's eye view" of everything we deployed.
kubectl -n multi-tier-app get all
```

### Watch pods in real-time

```bash
# The "-w" flag watches for changes — you'll see updates live.
# Press Ctrl+C to stop watching.
kubectl -n multi-tier-app get pods -w
```

### Kill a pod and watch Kubernetes self-heal

```bash
# Delete a backend pod. Kubernetes will immediately create a replacement.
# This is the whole point of Deployments — they maintain the desired replica count.
kubectl -n multi-tier-app delete pod -l app=backend --wait=false

# Watch the replacement pod spin up (usually takes ~10 seconds):
kubectl -n multi-tier-app get pods -w
```

### Read the logs

```bash
# See what the backend is doing. "-f" follows the log in real-time (like tail -f).
kubectl -n multi-tier-app logs -f deploy/backend

# In another terminal, make a request and watch the log update:
curl http://localhost/api/data
```

### Scale the backend up and down

```bash
# Scale to 4 replicas (double what we started with).
kubectl -n multi-tier-app scale deployment/backend --replicas=4

# Watch all 4 pods come up:
kubectl -n multi-tier-app get pods -l app=backend

# Scale back down to 2:
kubectl -n multi-tier-app scale deployment/backend --replicas=2
```

### Inspect a pod in detail

```bash
# "describe" shows everything about a resource: config, events, conditions.
# This is your go-to debugging command when something isn't working.
kubectl -n multi-tier-app describe pod postgres-0
```

### Exec into a running container

```bash
# Get a shell inside a backend pod — useful for debugging.
# You're now "inside" the container, as if you SSH'd into it.
kubectl -n multi-tier-app exec -it deploy/backend -- /bin/bash

# Inside the container, you can:
python -c "import psycopg2; print('DB driver loaded')"  # Test Python imports
env | grep DB_                                            # See environment variables
curl http://postgres:5432 2>&1 || echo "Port open"       # Test DB connectivity
exit                                                      # Leave the container
```

### Check resource usage

```bash
# See CPU and memory usage per pod (requires metrics-server, which k3s includes).
kubectl -n multi-tier-app top pods
```

### View the Ingress routing

```bash
# See the Ingress resource and its routing rules.
kubectl -n multi-tier-app get ingress
kubectl -n multi-tier-app describe ingress multi-tier-ingress
```

---

## Cleaning Up

When you're done experimenting and want to remove everything:

```bash
# Deleting the namespace removes EVERYTHING inside it — all pods, services,
# secrets, configmaps, deployments, statefulsets, and the PVC.
# This is the nuclear option — one command to clean it all up.
kubectl delete namespace multi-tier-app
```

To redeploy later, just start again from Step 3.

To also clean up the Docker images:

```bash
docker rmi multi-tier-backend:latest multi-tier-frontend:latest
```

---

## Troubleshooting

### "ImagePullBackOff" or "ErrImageNeverPull"

The images weren't imported into k3s properly. Re-run:
```bash
docker save multi-tier-backend:latest | sudo k3s ctr images import -
docker save multi-tier-frontend:latest | sudo k3s ctr images import -
```

### Pods stuck in "Pending"

Usually means not enough resources. Check:
```bash
kubectl -n multi-tier-app describe pod <pod-name>
```
Look at the "Events" section at the bottom for clues.

### Backend pods in "CrashLoopBackOff"

The backend can't connect to the database. Check:
```bash
# Is the database pod running?
kubectl -n multi-tier-app get pods -l app=postgres

# Check backend logs for the error message:
kubectl -n multi-tier-app logs deploy/backend
```

### Can't access from browser (connection refused)

```bash
# Check Traefik is running:
kubectl -n kube-system get pods -l app.kubernetes.io/name=traefik

# Check the Ingress has an address:
kubectl -n multi-tier-app get ingress

# Test locally on the Pi first:
curl http://localhost
```

### "502 Bad Gateway" in browser

The Ingress is working but the backend Service can't reach the pods:
```bash
# Are backend pods Ready?
kubectl -n multi-tier-app get pods -l app=backend

# Check the endpoints (should show pod IPs):
kubectl -n multi-tier-app get endpoints backend
```

---

## Resource Usage Summary

Here's roughly what this deployment uses on your 4GB Pi:

| Component | Memory Request | CPU Request |
|-----------|---------------|-------------|
| PostgreSQL (1 pod) | 256Mi | 250m |
| Backend (2 pods) | 128Mi x 2 = 256Mi | 100m x 2 = 200m |
| Frontend (2 pods) | 64Mi x 2 = 128Mi | 50m x 2 = 100m |
| **Total app** | **640Mi** | **550m** |
| k3s system overhead | ~500Mi | ~200m |
| **Grand total** | **~1.1Gi** | **~750m** |

With 4GB RAM and 4 CPU cores, you have plenty of headroom. Your Pi will still
be responsive for other tasks.
