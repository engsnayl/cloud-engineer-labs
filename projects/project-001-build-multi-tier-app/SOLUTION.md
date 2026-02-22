# Solution Walkthrough — Build From Scratch: Multi-Tier Application on Kubernetes

## The Project

Unlike the troubleshooting labs, this is a **build challenge**. There are no bugs to fix — you're given requirements and must design, containerise, and deploy a complete three-tier application on Kubernetes from scratch.

The application has three tiers:
1. **Frontend** — nginx serving static HTML + reverse proxying `/api/` requests to the backend
2. **Backend** — Python Flask REST API with `/api/health`, `/api/data`, and `/metrics` endpoints
3. **Database** — PostgreSQL with persistent storage, credentials via Secret, and an init script with sample data

Plus networking (Ingress, NetworkPolicy) and all the Kubernetes resources to tie it together.

## Thought Process

When building a multi-tier application on Kubernetes, an experienced engineer works bottom-up:

1. **Start with the database** — it has no dependencies. Get PostgreSQL running with persistent storage, credentials, and sample data first.
2. **Build the backend next** — it depends on the database. Write the API, containerise it, deploy it, and verify it can connect to the database.
3. **Build the frontend last** — it depends on the backend. Configure nginx to serve static files and proxy API requests.
4. **Add networking** — Ingress for external access, NetworkPolicy for security.
5. **Test each tier before moving on** — use `kubectl port-forward` to verify each component works before adding the next.

This bottom-up approach means each tier can be tested independently. If the backend can't connect to the database, you know the issue is in the backend configuration, not the database — because you already verified the database works.

## Step-by-Step Solution

---

### Phase 1: Database (PostgreSQL)

#### Step 1: Create the namespace

**File: `solution/k8s/namespace.yaml`**

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: multi-tier-app
```

**What this does:** Creates an isolated namespace for all project resources. Namespaces provide logical separation — all resources for this application live in `multi-tier-app`, making it easy to manage, monitor, and tear down as a unit.

#### Step 2: Create the database Secret

**File: `solution/k8s/database-secret.yaml`**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: database-credentials
  namespace: multi-tier-app
type: Opaque
data:
  POSTGRES_USER: YXBwdXNlcg==
  POSTGRES_PASSWORD: c2VjdXJlcGFzczEyMw==
  POSTGRES_DB: YXBwZGI=
```

**What this does:** Stores database credentials as base64-encoded values in a Kubernetes Secret. The values decode to:
- `POSTGRES_USER` = `appuser`
- `POSTGRES_PASSWORD` = `securepass123`
- `POSTGRES_DB` = `appdb`

To generate base64 values: `echo -n "appuser" | base64`. Secrets are the Kubernetes-native way to handle sensitive configuration. They're stored separately from application code and can be mounted as environment variables or files.

#### Step 3: Create the database init script ConfigMap

**File: `solution/k8s/database-init-configmap.yaml`**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: database-init
  namespace: multi-tier-app
data:
  init.sql: |
    CREATE TABLE IF NOT EXISTS items (
      id SERIAL PRIMARY KEY,
      name VARCHAR(100) NOT NULL,
      description TEXT,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );

    INSERT INTO items (name, description) VALUES
      ('Widget A', 'A standard widget for everyday use'),
      ('Widget B', 'A premium widget with extra features'),
      ('Gadget X', 'An innovative gadget for tech enthusiasts')
    ON CONFLICT DO NOTHING;
```

**What this does:** Contains the SQL script that runs when PostgreSQL starts for the first time. It creates an `items` table and inserts three sample rows. The `ON CONFLICT DO NOTHING` ensures the inserts are idempotent — if the database restarts, it won't duplicate the sample data. This ConfigMap gets mounted into PostgreSQL's `/docker-entrypoint-initdb.d/` directory, where the official postgres image automatically executes `.sql` files on first boot.

#### Step 4: Create the PersistentVolumeClaim

**File: `solution/k8s/database-pvc.yaml`**

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-data
  namespace: multi-tier-app
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
```

**What this does:** Requests 1GB of persistent storage for PostgreSQL data. `ReadWriteOnce` means one node can mount the volume at a time (appropriate for a single-replica database). The PVC ensures data survives pod restarts — if the PostgreSQL pod crashes and is rescheduled, it reconnects to the same volume with all data intact. Without a PVC, all database data is lost when the pod restarts.

#### Step 5: Create the database StatefulSet

**File: `solution/k8s/database-statefulset.yaml`**

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: multi-tier-app
spec:
  serviceName: postgres
  replicas: 1
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:15
          ports:
            - containerPort: 5432
          envFrom:
            - secretRef:
                name: database-credentials
          volumeMounts:
            - name: postgres-data
              mountPath: /var/lib/postgresql/data
              subPath: pgdata
            - name: init-scripts
              mountPath: /docker-entrypoint-initdb.d
      volumes:
        - name: postgres-data
          persistentVolumeClaim:
            claimName: postgres-data
        - name: init-scripts
          configMap:
            name: database-init
```

**What this does:** Deploys PostgreSQL as a StatefulSet (not a Deployment), which is the correct Kubernetes resource for databases because:
- **Stable network identity** — the pod always gets the name `postgres-0`, making it predictable for DNS.
- **Ordered operations** — StatefulSets start and stop pods in order, which matters for databases.
- **Persistent storage** — paired with the PVC, data persists across pod restarts.

Key details:
- `envFrom.secretRef` injects all Secret keys as environment variables (`POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`).
- `subPath: pgdata` is required because PostgreSQL expects an empty directory. Without the subPath, the PVC's root (which may contain a `lost+found` directory) causes postgres to fail.
- The init script ConfigMap is mounted at `/docker-entrypoint-initdb.d/`, where postgres auto-executes it on first start.

#### Step 6: Create the database Service

**File: `solution/k8s/database-service.yaml`**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres
  namespace: multi-tier-app
spec:
  selector:
    app: postgres
  ports:
    - port: 5432
      targetPort: 5432
  clusterIP: None
```

**What this does:** Creates a headless Service (`clusterIP: None`) for the StatefulSet. A headless Service is used because:
- StatefulSets need a `serviceName` that matches a headless Service.
- It creates a DNS record `postgres-0.postgres.multi-tier-app.svc.cluster.local` for the specific pod.
- The backend can connect to `postgres` (the Service name) which resolves to the pod directly.

---

### Phase 2: Backend API

#### Step 7: Write the backend application

**File: `solution/docker/backend/app.py`**

```python
from flask import Flask, jsonify
import psycopg2
import os

app = Flask(__name__)

def get_db_connection():
    return psycopg2.connect(
        host=os.environ.get('DATABASE_HOST', 'postgres'),
        port=os.environ.get('DATABASE_PORT', '5432'),
        dbname=os.environ.get('DATABASE_NAME', 'appdb'),
        user=os.environ.get('DATABASE_USER', 'appuser'),
        password=os.environ.get('DATABASE_PASSWORD', 'securepass123')
    )

@app.route('/api/health')
def health():
    try:
        conn = get_db_connection()
        conn.close()
        return jsonify({'status': 'healthy', 'database': 'connected'})
    except Exception as e:
        return jsonify({'status': 'unhealthy', 'error': str(e)}), 503

@app.route('/api/data')
def data():
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute('SELECT id, name, description FROM items')
        rows = cur.fetchall()
        cur.close()
        conn.close()
        items = [{'id': r[0], 'name': r[1], 'description': r[2]} for r in rows]
        return jsonify({'items': items})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/metrics')
def metrics():
    return (
        '# HELP http_requests_total Total HTTP requests\n'
        '# TYPE http_requests_total counter\n'
        'http_requests_total{endpoint="/api/health"} 0\n'
        'http_requests_total{endpoint="/api/data"} 0\n'
        '# HELP app_info Application information\n'
        '# TYPE app_info gauge\n'
        'app_info{version="1.0.0"} 1\n'
    ), 200, {'Content-Type': 'text/plain'}

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
```

**What this does:** A Flask application with three endpoints:
- `/api/health` — checks database connectivity and returns health status. Used by Kubernetes liveness/readiness probes.
- `/api/data` — queries `SELECT * FROM items` and returns results as JSON. This is the main data endpoint.
- `/metrics` — exposes Prometheus-format metrics for monitoring. In a production app, you'd use the `prometheus_client` library for real metrics.

Database connection details come from environment variables (injected via ConfigMap and Secret), with sensible defaults.

#### Step 8: Create the backend Dockerfile

**File: `solution/docker/backend/Dockerfile`**

```dockerfile
FROM python:3.11-slim

WORKDIR /app

RUN pip install --no-cache-dir flask psycopg2-binary

COPY app.py .

EXPOSE 8080

CMD ["python", "app.py"]
```

**What this does:** Builds a minimal container for the Flask API:
- `python:3.11-slim` — small base image with Python pre-installed.
- `psycopg2-binary` — PostgreSQL adapter for Python. The `-binary` variant includes libpq so we don't need to install system packages.
- `EXPOSE 8080` — documents the port (informational; the actual port binding is in the app code).
- `CMD` starts the Flask development server on port 8080.

#### Step 9: Create the backend ConfigMap

**File: `solution/k8s/backend-configmap.yaml`**

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: backend-config
  namespace: multi-tier-app
data:
  DATABASE_HOST: "postgres"
  DATABASE_PORT: "5432"
  DATABASE_NAME: "appdb"
  DATABASE_USER: "appuser"
```

**What this does:** Stores non-sensitive database configuration as a ConfigMap. The password is NOT included here — it comes from the Secret. ConfigMaps are for configuration values that aren't secret (hostnames, ports, database names). Separating config from code means you can change the database hostname without rebuilding the Docker image.

#### Step 10: Create the backend Deployment

**File: `solution/k8s/backend-deployment.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: backend
  namespace: multi-tier-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: backend
  template:
    metadata:
      labels:
        app: backend
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
        prometheus.io/path: "/metrics"
    spec:
      containers:
        - name: backend
          image: backend:latest
          ports:
            - containerPort: 8080
          envFrom:
            - configMapRef:
                name: backend-config
          env:
            - name: DATABASE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: database-credentials
                  key: POSTGRES_PASSWORD
          readinessProbe:
            httpGet:
              path: /api/health
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /api/health
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 30
```

**What this does:** Deploys 2 replicas of the backend API:
- `envFrom.configMapRef` injects all ConfigMap keys as environment variables.
- The password is injected separately from the Secret using `secretKeyRef`.
- **Readiness probe** — Kubernetes only sends traffic to the pod after `/api/health` returns 200. This prevents traffic hitting a pod that hasn't connected to the database yet.
- **Liveness probe** — if `/api/health` fails consistently, Kubernetes restarts the pod.
- **Prometheus annotations** — standard annotations that Prometheus uses for auto-discovery scraping.

#### Step 11: Create the backend Service

**File: `solution/k8s/backend-service.yaml`**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: backend-service
  namespace: multi-tier-app
spec:
  selector:
    app: backend
  ports:
    - port: 8080
      targetPort: 8080
```

**What this does:** Creates a ClusterIP Service (the default) that load-balances traffic across the 2 backend replicas. The frontend's nginx proxy sends requests to `backend-service:8080`, and Kubernetes distributes them across healthy backend pods.

---

### Phase 3: Frontend (nginx)

#### Step 12: Create the frontend HTML

**File: `solution/docker/frontend/index.html`**

```html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Multi-Tier App</title>
    <style>
        body { font-family: sans-serif; max-width: 800px; margin: 40px auto; padding: 0 20px; }
        h1 { color: #333; }
        #data { margin-top: 20px; }
        .item { background: #f5f5f5; padding: 12px; margin: 8px 0; border-radius: 4px; }
        .status { padding: 8px; border-radius: 4px; margin: 10px 0; }
        .healthy { background: #d4edda; color: #155724; }
        .error { background: #f8d7da; color: #721c24; }
    </style>
</head>
<body>
    <h1>Multi-Tier Application</h1>
    <div id="health"></div>
    <h2>Items from Database</h2>
    <div id="data">Loading...</div>
    <script>
        fetch('/api/health')
            .then(r => r.json())
            .then(d => {
                document.getElementById('health').innerHTML =
                    `<div class="status healthy">Backend: ${d.status} | DB: ${d.database}</div>`;
            })
            .catch(() => {
                document.getElementById('health').innerHTML =
                    '<div class="status error">Backend unreachable</div>';
            });

        fetch('/api/data')
            .then(r => r.json())
            .then(d => {
                document.getElementById('data').innerHTML = d.items
                    .map(i => `<div class="item"><strong>${i.name}</strong><br>${i.description}</div>`)
                    .join('');
            })
            .catch(() => {
                document.getElementById('data').innerHTML = '<div class="status error">Failed to load data</div>';
            });
    </script>
</body>
</html>
```

**What this does:** A simple single-page frontend that:
- Calls `/api/health` to show the backend and database status.
- Calls `/api/data` to display items from the database.
- Both calls go through nginx's reverse proxy (see next step), which forwards `/api/` requests to the backend Service.

#### Step 13: Create the nginx configuration

**File: `solution/docker/frontend/nginx.conf`**

```nginx
server {
    listen 80;

    location / {
        root /usr/share/nginx/html;
        index index.html;
        try_files $uri $uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://backend-service:8080/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**What this does:** Configures nginx with two routing rules:
- `/` — serves static HTML files from `/usr/share/nginx/html` (where index.html is copied). `try_files` supports single-page app routing.
- `/api/` — reverse proxies to `backend-service:8080`. The `proxy_set_header` lines forward the original client information to the backend, which is important for logging and security. The trailing `/` in `proxy_pass` means `/api/health` on the frontend becomes `/api/health` on the backend (path is preserved).

#### Step 14: Create the frontend Dockerfile

**File: `solution/docker/frontend/Dockerfile`**

```dockerfile
FROM nginx:alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html /usr/share/nginx/html/index.html

EXPOSE 80
```

**What this does:** Builds a minimal nginx container:
- `nginx:alpine` — lightweight base image (~5MB).
- Copies the custom nginx config to the default server block location.
- Copies the static HTML to nginx's default document root.
- The container serves static files and proxies API requests without any additional runtime.

#### Step 15: Create the frontend Deployment

**File: `solution/k8s/frontend-deployment.yaml`**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: multi-tier-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
        - name: frontend
          image: frontend:latest
          ports:
            - containerPort: 80
          readinessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 2
            periodSeconds: 10
```

**What this does:** Deploys 2 replicas of the frontend nginx container. The readiness probe checks that nginx is serving the root page before Kubernetes sends traffic to the pod. Two replicas provide high availability — if one pod crashes, the other continues serving traffic.

#### Step 16: Create the frontend Service

**File: `solution/k8s/frontend-service.yaml`**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: frontend-service
  namespace: multi-tier-app
spec:
  selector:
    app: frontend
  ports:
    - port: 80
      targetPort: 80
```

**What this does:** Creates a ClusterIP Service for the frontend. The Ingress controller routes external traffic to this Service, which distributes it across the 2 frontend pods.

---

### Phase 4: Networking

#### Step 17: Create the Ingress

**File: `solution/k8s/ingress.yaml`**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  namespace: multi-tier-app
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  rules:
    - http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: backend-service
                port:
                  number: 8080
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend-service
                port:
                  number: 80
```

**What this does:** Configures external HTTP routing:
- `/api/*` requests go directly to the backend Service (port 8080). The `/api` path is listed first because Ingress matches the most specific path.
- `/` (everything else) goes to the frontend Service (port 80).

This provides a single entry point for the entire application. Users access the frontend at `/` and the frontend's JavaScript calls `/api/data`, which the Ingress routes to the backend. Alternatively, nginx inside the frontend can handle the proxying (which it already does) — the Ingress gives you the flexibility of either approach.

#### Step 18: Create the NetworkPolicy

**File: `solution/k8s/network-policy.yaml`**

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: database-access
  namespace: multi-tier-app
spec:
  podSelector:
    matchLabels:
      app: postgres
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: backend
      ports:
        - protocol: TCP
          port: 5432
```

**What this does:** Restricts database access so that **only backend pods can connect to PostgreSQL**. This is a critical security control:
- `podSelector: app: postgres` — this policy applies to the database pods.
- `ingress.from.podSelector: app: backend` — only pods with the label `app: backend` can send traffic.
- `ports: 5432` — and only on the PostgreSQL port.

Without this NetworkPolicy, any pod in the namespace (including the frontend) could connect directly to the database. In a real attack scenario, a compromised frontend pod could access or modify the database directly. The NetworkPolicy enforces the principle of least privilege — only the backend tier needs database access.

---

### Phase 5: Architecture Documentation

#### Step 19: Create the README

**File: `solution/README.md`**

```markdown
# Multi-Tier Application — Architecture Documentation

## Architecture Overview

```
                    ┌──────────┐
                    │  Ingress │
                    └────┬─────┘
                         │
              ┌──────────┴──────────┐
              │                     │
         /api/* route          / route
              │                     │
    ┌─────────▼──────────┐  ┌──────▼────────┐
    │  Backend Service   │  │Frontend Service│
    │  (ClusterIP:8080)  │  │ (ClusterIP:80) │
    └─────────┬──────────┘  └───────────────┘
              │
    ┌─────────▼──────────┐
    │  Backend Pods (x2) │
    │  Flask API         │
    └─────────┬──────────┘
              │ port 5432 (NetworkPolicy enforced)
    ┌─────────▼──────────┐
    │  PostgreSQL        │
    │  StatefulSet (x1)  │
    │  + PVC (1Gi)       │
    └────────────────────┘
```

## Technology Choices

| Component | Choice | Rationale |
|-----------|--------|-----------|
| Frontend | nginx:alpine | Lightweight, proven reverse proxy, serves static files efficiently |
| Backend | Python 3.11 + Flask | Simple to write, widely understood, good PostgreSQL support |
| Database | PostgreSQL 15 | Production-grade relational database, official Docker image handles init scripts |
| Container base | Alpine/Slim variants | Minimal attack surface, small image sizes |

## Communication Patterns

1. **User → Frontend**: HTTP on port 80 via Ingress
2. **Frontend → Backend**: nginx reverse proxy forwards `/api/` to `backend-service:8080`
3. **Backend → Database**: psycopg2 connects to `postgres:5432` using credentials from Secret

## Kubernetes Resources

- **Namespace**: `multi-tier-app` — isolates all resources
- **StatefulSet**: PostgreSQL (stable identity, persistent storage)
- **Deployments**: Frontend (2 replicas), Backend (2 replicas)
- **Services**: Headless for PostgreSQL, ClusterIP for frontend and backend
- **ConfigMap**: Backend database config (non-sensitive), database init SQL script
- **Secret**: Database credentials (base64-encoded)
- **PVC**: 1Gi for PostgreSQL data persistence
- **Ingress**: Path-based routing to frontend and backend
- **NetworkPolicy**: Restricts database access to backend pods only

## Production Considerations

For a real production deployment, add:

1. **TLS/HTTPS**: Add cert-manager for automatic Let's Encrypt certificates on the Ingress
2. **Resource limits**: Set CPU/memory requests and limits on all containers to prevent resource starvation
3. **HPA (Horizontal Pod Autoscaler)**: Auto-scale frontend and backend based on CPU/request metrics
4. **Database backups**: Scheduled pg_dump to S3, or use a managed database service (RDS)
5. **Secrets management**: Use External Secrets Operator with AWS Secrets Manager instead of Kubernetes Secrets
6. **Health checks**: Already implemented — readiness and liveness probes on all tiers
7. **Monitoring**: Prometheus ServiceMonitor for backend metrics, Grafana dashboards
8. **Log aggregation**: Fluent Bit sidecar or DaemonSet forwarding logs to Elasticsearch/CloudWatch
9. **Database connection pooling**: PgBouncer between backend and PostgreSQL for connection management
10. **Image registry**: Push images to ECR/GCR with specific version tags, never use `latest` in production
```

**What this does:** Documents every architectural decision, explains how the components communicate, and outlines what would need to change for production. This is exactly what interviewers look for in a take-home assessment — not just working code, but evidence that you understand the trade-offs and can plan for production.

---

### Phase 6: Deploy and Validate

#### Step 20: Build the Docker images

```bash
# Build frontend image
docker build -t frontend:latest solution/docker/frontend/

# Build backend image
docker build -t backend:latest solution/docker/backend/
```

#### Step 21: Deploy to Kubernetes (in order)

```bash
# 1. Namespace first
kubectl apply -f solution/k8s/namespace.yaml

# 2. Database tier (Secret → PVC → Init ConfigMap → StatefulSet → Service)
kubectl apply -f solution/k8s/database-secret.yaml
kubectl apply -f solution/k8s/database-pvc.yaml
kubectl apply -f solution/k8s/database-init-configmap.yaml
kubectl apply -f solution/k8s/database-statefulset.yaml
kubectl apply -f solution/k8s/database-service.yaml

# 3. Wait for database to be ready
kubectl wait --for=condition=ready pod/postgres-0 -n multi-tier-app --timeout=60s

# 4. Backend tier
kubectl apply -f solution/k8s/backend-configmap.yaml
kubectl apply -f solution/k8s/backend-deployment.yaml
kubectl apply -f solution/k8s/backend-service.yaml

# 5. Frontend tier
kubectl apply -f solution/k8s/frontend-deployment.yaml
kubectl apply -f solution/k8s/frontend-service.yaml

# 6. Networking
kubectl apply -f solution/k8s/ingress.yaml
kubectl apply -f solution/k8s/network-policy.yaml
```

**What this does:** Deploys resources in dependency order. The database must be running before the backend starts (so the health check and init queries succeed). The backend must be running before the frontend proxies to it. The `kubectl wait` command pauses until PostgreSQL is ready, preventing the backend from starting before the database is available.

#### Step 22: Test each tier

```bash
# Test database
kubectl exec -n multi-tier-app postgres-0 -- psql -U appuser -d appdb -c "SELECT * FROM items;"

# Test backend
kubectl port-forward -n multi-tier-app svc/backend-service 8080:8080 &
curl http://localhost:8080/api/health
curl http://localhost:8080/api/data

# Test frontend
kubectl port-forward -n multi-tier-app svc/frontend-service 8081:80 &
curl http://localhost:8081/

# Test data persistence (restart postgres and verify data survives)
kubectl delete pod postgres-0 -n multi-tier-app
kubectl wait --for=condition=ready pod/postgres-0 -n multi-tier-app --timeout=60s
kubectl exec -n multi-tier-app postgres-0 -- psql -U appuser -d appdb -c "SELECT count(*) FROM items;"
# Should still return 3 rows
```

#### Step 23: Run validation

```bash
bash validate.sh
```

## Docker Lab vs Real Life

- **Managed databases:** In production, use RDS, Cloud SQL, or Aurora instead of running PostgreSQL in Kubernetes. Managed databases handle backups, failover, patching, and scaling automatically.
- **Helm charts:** Instead of individual YAML files, production deployments use Helm charts with values files for each environment (dev, staging, prod). One chart, different configurations.
- **GitOps:** ArgoCD or Flux automatically syncs Kubernetes manifests from a git repository. Push to git → cluster updates automatically.
- **Service mesh:** Istio or Linkerd adds mutual TLS, traffic management, and observability between services without changing application code.
- **CI/CD pipeline:** In production, a GitHub Actions or GitLab CI pipeline builds images, pushes to a registry, and updates the Kubernetes manifests. No manual `kubectl apply`.

## Key Concepts Learned

- **Build bottom-up** — start with the database (no dependencies), then backend (depends on DB), then frontend (depends on backend). Test each tier independently before moving on.
- **StatefulSet for databases, Deployment for stateless services** — StatefulSets provide stable identity and persistent storage. Deployments provide easy scaling and rolling updates.
- **Separate sensitive and non-sensitive config** — Secrets for passwords, ConfigMaps for hostnames and ports. Never mix credentials into ConfigMaps.
- **NetworkPolicy enforces least privilege** — only the backend needs database access. Block everything else. This limits blast radius if any pod is compromised.
- **Document your architecture** — working code isn't enough. A README explaining choices, communication patterns, and production considerations shows you understand the system, not just the syntax.

## Common Mistakes

- **Deploying out of order** — starting the backend before the database is ready causes CrashLoopBackOff. Always deploy dependencies first and wait for them to be ready.
- **Forgetting `subPath` on PostgreSQL volume mounts** — mounting a PVC directly at `/var/lib/postgresql/data` fails because the volume may contain a `lost+found` directory. The `subPath: pgdata` creates a clean subdirectory.
- **Using Deployment instead of StatefulSet for databases** — Deployments don't guarantee stable pod names or ordered operations. StatefulSets are designed for stateful workloads.
- **Putting passwords in ConfigMaps** — ConfigMaps are not encrypted and are visible to anyone with namespace access. Always use Secrets for credentials.
- **No readiness probes** — without readiness probes, Kubernetes sends traffic to pods that aren't ready yet. The backend needs to verify database connectivity before receiving traffic.
- **NetworkPolicy without testing** — apply the NetworkPolicy and then verify the frontend can NOT connect to PostgreSQL directly. If it can, the policy isn't working (possibly because the CNI plugin doesn't support NetworkPolicies).
