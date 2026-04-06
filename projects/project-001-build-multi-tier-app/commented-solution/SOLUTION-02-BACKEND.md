# Solution Walkthrough: Part 2 — Backend Layer

## What This Layer Does

The backend is the **application logic** tier. It receives HTTP requests, processes them, talks to the database, and returns JSON responses. It's the bridge between what the user sees (frontend) and where data lives (database).

## Files in This Layer

| File | Purpose |
|------|---------|
| `docker/backend/app.py` | Flask REST API application |
| `docker/backend/requirements.txt` | Python package dependencies |
| `docker/backend/Dockerfile` | Container build instructions |
| `k8s/backend-configmap.yaml` | Database connection settings |
| `k8s/backend-deployment.yaml` | Pod management with health probes |
| `k8s/backend-service.yaml` | Internal load balancer for backend pods |

## The Flask Application (app.py)

### Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/health` | GET | Health check — tells Kubernetes if the pod is alive and connected to the DB |
| `/api/data` | GET | Returns all items from the database as JSON |
| `/api/data` | POST | Creates a new item (expects JSON body with `name` field) |
| `/metrics` | GET | Returns request counts for monitoring |

### Why Environment Variables for Configuration?

The app reads database connection details from environment variables:
```python
host = os.environ.get("DB_HOST", "postgres")
```

This is one of the [12-Factor App](https://12factor.net/) principles: **store config in the environment**. The same container image can connect to different databases (dev, staging, prod) just by changing environment variables — no code change, no rebuild needed.

In Kubernetes, these variables are injected from:
- **ConfigMap** (`backend-configmap.yaml`) → non-sensitive settings (host, port, db name)
- **Secret** (`postgres-secret.yaml`) → sensitive settings (username, password)

### Why parameterized queries matter

In `app.py`, you'll see:
```python
cur.execute(
    "INSERT INTO items (name, description) VALUES (%s, %s) RETURNING *",
    (body["name"], body.get("description", "")),
)
```

The `%s` placeholders are **parameterized** — psycopg2 escapes the values before putting them into the SQL. This prevents **SQL injection**, where an attacker could send `"; DROP TABLE items; --` as a name and destroy your data.

Never do this instead:
```python
# DANGEROUS — never build SQL with f-strings!
cur.execute(f"INSERT INTO items (name) VALUES ('{body['name']}')")
```

### Why Gunicorn Instead of Flask's Built-in Server?

Flask's `app.run()` is a **development** server — it handles one request at a time and has no worker management. Gunicorn is a production WSGI server that:
- Runs multiple worker processes (we use 2)
- Handles concurrent requests properly
- Restarts crashed workers automatically
- Manages graceful shutdowns

The Dockerfile uses Gunicorn as the entrypoint:
```dockerfile
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "app:app"]
```

## The Dockerfile

### Why Copy requirements.txt First?

```dockerfile
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
```

Docker builds images in **layers**, and each layer is cached. By copying requirements.txt separately:
- If your code changes but dependencies don't → Docker reuses the cached pip install layer (fast!)
- If requirements.txt changes → Docker reinstalls packages (necessary, but slower)

If you did `COPY . .` first and then `pip install`, changing *any* file in your code would invalidate the cache and force a full reinstall every time.

## The Kubernetes Manifests

### ConfigMap vs Secret — When to Use Which?

| Data | Where to Store | Why |
|------|---------------|-----|
| Database hostname | ConfigMap | Not sensitive — it's just a DNS name |
| Database port | ConfigMap | Standard port number, not secret |
| Database name | ConfigMap | Not sensitive by itself |
| Database username | Secret | Credentials should be protected |
| Database password | Secret | Definitely sensitive |

The rule of thumb: **if you'd be uncomfortable seeing it on a public screen, it's a Secret.**

### Health Probes Explained

The Deployment defines two probes:

**Readiness Probe** — "Can this pod handle traffic?"
```yaml
readinessProbe:
  httpGet:
    path: /api/health
    port: 5000
  initialDelaySeconds: 5
  periodSeconds: 10
```
- Runs every 10 seconds after an initial 5-second wait
- If it fails, the pod is removed from the Service (stops receiving traffic)
- The pod is NOT restarted — it just stops getting new requests
- When it passes again, the pod is added back to the Service

**Liveness Probe** — "Is this pod still alive?"
```yaml
livenessProbe:
  httpGet:
    path: /api/health
    port: 5000
  initialDelaySeconds: 15
  periodSeconds: 20
```
- Runs every 20 seconds after an initial 15-second wait
- If it fails 3 times in a row, the pod is **killed and restarted**
- This catches deadlocks and other "alive but broken" states

The longer initial delay for liveness (15s vs 5s for readiness) gives the app time to start up. You don't want Kubernetes killing the pod before it's had a chance to boot.

### envFrom vs env

The Deployment uses both methods:

```yaml
envFrom:
  - configMapRef:
      name: backend-config    # Imports ALL keys as env vars

env:
  - name: DB_USER
    valueFrom:
      secretKeyRef:
        name: postgres-secret
        key: POSTGRES_USER    # Imports ONE specific key
```

- `envFrom` is a bulk import — every key in the ConfigMap becomes an environment variable
- `env` with `valueFrom` imports individual keys and lets you rename them (e.g., `POSTGRES_USER` → `DB_USER`)

## Testing This Layer

```bash
# Port-forward to test the backend directly (bypasses nginx)
kubectl -n multi-tier-app port-forward svc/backend 5000:5000

# In another terminal:
curl http://localhost:5000/api/health
curl http://localhost:5000/api/data
curl -X POST http://localhost:5000/api/data \
  -H "Content-Type: application/json" \
  -d '{"name": "Test Item", "description": "Created via curl"}'
```

## Common Issues

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Pods in `CrashLoopBackOff` | Image not found locally | Build image with `eval $(minikube docker-env)` first |
| Health check failing | Database not ready yet | Deploy database first and wait for it to be Ready |
| `Connection refused` on port-forward | Pod not ready | Check `kubectl get pods` — wait for `2/2 Ready` |
| `FATAL: password authentication failed` | Secret values mismatch | Decode all base64 values and verify they match |
