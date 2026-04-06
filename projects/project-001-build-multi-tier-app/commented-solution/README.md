# Multi-Tier Kubernetes Application — Commented Solution

## Architecture Overview

This project deploys a three-tier web application on Kubernetes:

```
                          ┌─────────────┐
                          │   Browser   │
                          └──────┬──────┘
                                 │
                          ┌──────▼──────┐
                          │   Ingress   │
                          │ (path-based │
                          │   routing)  │
                          └──┬───────┬──┘
                             │       │
                   /         │       │  /api/*
                             │       │
                    ┌────────▼──┐ ┌──▼─────────┐
                    │  Frontend │ │   Backend   │
                    │   nginx   │ │    Flask    │
                    │  (port 80)│ │ (port 5000) │
                    │ 2 replicas│ │  2 replicas │
                    └───────────┘ └──────┬──────┘
                                         │
                                  ┌──────▼──────┐
                                  │ PostgreSQL  │
                                  │ StatefulSet │
                                  │ (port 5432) │
                                  │ 1 replica   │
                                  │ + PVC (1Gi) │
                                  └─────────────┘
```

## Tier Responsibilities

| Tier | Technology | Purpose |
|------|-----------|---------|
| **Frontend** | nginx 1.25 (Alpine) | Serves static HTML, proxies `/api/` requests to backend |
| **Backend** | Python 3.11 + Flask | REST API with `/api/health`, `/api/data`, and `/metrics` endpoints |
| **Database** | PostgreSQL 15 | Persistent data storage via StatefulSet + PVC |

## Image Selection Rationale

- **nginx:1.25-alpine** — Alpine base keeps the image tiny (~40MB). Nginx is battle-tested for static file serving and reverse proxying.
- **python:3.11-slim** — Slim variant removes dev tools we don't need while keeping glibc compatibility. Python 3.11 has significant performance improvements over earlier versions.
- **postgres:15** — The official image includes built-in support for init scripts via `/docker-entrypoint-initdb.d/`. Version 15 is a stable LTS release.

## Inter-Service Communication

Services communicate using Kubernetes DNS:

1. **Browser → Ingress** — External HTTP traffic enters the cluster
2. **Ingress → Frontend/Backend** — Path-based routing: `/` to frontend, `/api/*` to backend
3. **Frontend (nginx) → Backend** — Nginx `proxy_pass` to `http://backend:5000`
4. **Backend → Database** — psycopg2 connects to `postgres:5432` (Service DNS name)

All internal communication uses ClusterIP Services (cluster-internal only). The Ingress is the only external entry point.

## Security

- **NetworkPolicy** restricts database access to backend pods only (port 5432)
- **Secrets** store database credentials (base64-encoded)
- **Parameterized SQL queries** prevent SQL injection in the backend

## File Structure

```
commented-solution/
├── docker/
│   ├── frontend/
│   │   ├── Dockerfile          # Builds the nginx container image
│   │   ├── nginx.conf          # Web server + reverse proxy configuration
│   │   └── index.html          # Single-page frontend application
│   └── backend/
│       ├── Dockerfile          # Builds the Flask API container image
│       ├── app.py              # Flask REST API application
│       └── requirements.txt    # Python package dependencies
├── k8s/
│   ├── namespace.yaml          # Isolated namespace for the project
│   ├── postgres-secret.yaml    # Database credentials
│   ├── postgres-init-configmap.yaml  # SQL init script
│   ├── postgres-statefulset.yaml     # Database pod with persistent storage
│   ├── postgres-service.yaml         # Headless Service for the database
│   ├── backend-configmap.yaml        # Backend environment configuration
│   ├── backend-deployment.yaml       # Backend pod management
│   ├── backend-service.yaml          # Backend load balancer
│   ├── frontend-deployment.yaml      # Frontend pod management
│   ├── frontend-service.yaml         # Frontend load balancer
│   ├── ingress.yaml                  # External traffic routing
│   └── network-policy.yaml           # Database firewall rules
├── README.md                   # This file
├── SOLUTION-00-OVERVIEW.md     # Architecture walkthrough
├── SOLUTION-01-DATABASE.md     # Database tier walkthrough
├── SOLUTION-02-BACKEND.md      # Backend tier walkthrough
├── SOLUTION-03-FRONTEND.md     # Frontend tier walkthrough
├── SOLUTION-04-NETWORKING.md   # Ingress + NetworkPolicy walkthrough
└── SOLUTION-05-OBSERVABILITY.md # Metrics endpoint walkthrough
```

## Build & Deploy Instructions

### Prerequisites

- Docker installed
- A Kubernetes cluster (minikube, kind, or cloud-managed)
- kubectl configured to talk to your cluster
- An Ingress Controller installed (e.g., `minikube addons enable ingress`)

### Step 1: Create the Namespace

```bash
kubectl apply -f k8s/namespace.yaml
```

### Step 2: Build Container Images

```bash
# If using minikube, point Docker to minikube's daemon first:
eval $(minikube docker-env)

# Build the images
docker build -t multi-tier-backend:latest docker/backend/
docker build -t multi-tier-frontend:latest docker/frontend/
```

### Step 3: Deploy Database Layer

```bash
kubectl apply -f k8s/postgres-secret.yaml
kubectl apply -f k8s/postgres-init-configmap.yaml
kubectl apply -f k8s/postgres-statefulset.yaml
kubectl apply -f k8s/postgres-service.yaml

# Wait for the database to be ready
kubectl -n multi-tier-app wait --for=condition=Ready pod/postgres-0 --timeout=120s
```

### Step 4: Deploy Backend Layer

```bash
kubectl apply -f k8s/backend-configmap.yaml
kubectl apply -f k8s/backend-deployment.yaml
kubectl apply -f k8s/backend-service.yaml

# Test with port-forward
kubectl -n multi-tier-app port-forward svc/backend 5000:5000 &
curl http://localhost:5000/api/health
```

### Step 5: Deploy Frontend Layer

```bash
kubectl apply -f k8s/frontend-deployment.yaml
kubectl apply -f k8s/frontend-service.yaml
```

### Step 6: Configure Networking

```bash
kubectl apply -f k8s/ingress.yaml
kubectl apply -f k8s/network-policy.yaml
```

### Step 7: Access the Application

```bash
# For minikube:
minikube ip
# Then open http://<minikube-ip> in your browser

# Or use minikube tunnel for localhost access:
minikube tunnel
# Then open http://localhost
```

## Production Considerations

This solution is built for learning. A production deployment would additionally need:

| Concern | Learning Version | Production Version |
|---------|-----------------|-------------------|
| **Database** | PostgreSQL in K8s StatefulSet | Managed service (RDS, Cloud SQL, Azure DB) |
| **TLS/HTTPS** | No encryption | cert-manager with Let's Encrypt certificates |
| **Scaling** | Fixed replica count | Horizontal Pod Autoscaler based on CPU/memory |
| **Secrets** | K8s Secrets (base64) | External Secrets Operator + HashiCorp Vault |
| **Monitoring** | Simple `/metrics` endpoint | Prometheus + Grafana stack |
| **Logging** | Container stdout | EFK/ELK stack or cloud-native logging |
| **Backups** | None | Automated database backups with retention policy |
| **Resource Limits** | Generous estimates | Tuned based on load testing |
