Title: Build From Scratch — Multi-Tier Application on Kubernetes
Difficulty: ⭐⭐⭐⭐ (Expert)
Time: 60-90 minutes
Category: End-to-End / Design & Build
Skills: Docker, Kubernetes, Helm, Terraform, networking, storage, monitoring — everything combined

## Scenario

Unlike the troubleshooting labs, this is a BUILD challenge. You're starting from scratch. No bugs to fix — just requirements to meet.

A startup needs their application deployed to Kubernetes. You need to containerise it, write the Kubernetes manifests (or Helm chart), configure networking, persistence, and basic monitoring.

## Requirements

### Tier 1: Frontend (nginx)
- Serves static HTML on port 80
- Reverse proxies `/api/` requests to the backend
- 2 replicas with a Service (ClusterIP or LoadBalancer)

### Tier 2: Backend API (Python or Node.js)
- Simple REST API with `/api/health` and `/api/data` endpoints
- `/api/data` reads from the database
- 2 replicas with a Service
- ConfigMap for database connection string

### Tier 3: Database (PostgreSQL)
- Single replica StatefulSet
- PersistentVolumeClaim for data
- Secret for database credentials (username/password)
- Init script to create a table with sample data

### Networking
- Ingress routing: `/` → frontend, `/api/` → backend
- Network Policy: only backend can talk to database

### Monitoring
- Backend exposes `/metrics` endpoint
- (Bonus) Prometheus ServiceMonitor or scrape annotation

## Deliverables

Create these files in the `solution/` directory:

```
solution/
├── docker/
│   ├── frontend/
│   │   ├── Dockerfile
│   │   ├── nginx.conf
│   │   └── index.html
│   └── backend/
│       ├── Dockerfile
│       └── app.py (or server.js)
├── k8s/
│   ├── namespace.yaml
│   ├── frontend-deployment.yaml
│   ├── frontend-service.yaml
│   ├── backend-deployment.yaml
│   ├── backend-service.yaml
│   ├── backend-configmap.yaml
│   ├── database-statefulset.yaml
│   ├── database-service.yaml
│   ├── database-secret.yaml
│   ├── database-init-configmap.yaml
│   ├── database-pvc.yaml
│   ├── ingress.yaml
│   └── network-policy.yaml
└── README.md (your architecture decisions)
```

## Validation Criteria

- All Docker images build successfully
- All K8s resources create without errors
- Frontend serves static content
- Backend responds to /api/health and /api/data
- Database is persistent (survives pod restart)
- Network policy restricts database access
- README documents your architecture

## Tips

- Start with the database (it has no dependencies)
- Then build the backend (depends on DB)
- Then the frontend (depends on backend)
- Add networking last (ingress, network policy)
- Test each tier before moving to the next
- Use `kubectl port-forward` to test services before ingress is ready

## What You're Practising

This is the kind of task you might get in a technical interview or take-home assessment. It tests whether you can take requirements and build a working system end-to-end, not just fix bugs in existing config. Interviewers want to see that you can make architectural decisions, not just troubleshoot.
