# Hints — Project 001: Multi-Tier Application

## Hint 1 — Database first
Start with PostgreSQL. A simple StatefulSet with a PVC:
```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres
  replicas: 1
  ...
```
Use the official `postgres:15` image. Set POSTGRES_PASSWORD via a Secret.

## Hint 2 — Backend
A simple Python Flask or Node.js Express API. Use a ConfigMap for DATABASE_HOST. The `/api/data` endpoint just runs `SELECT * FROM items` and returns JSON.

## Hint 3 — Frontend nginx config
```nginx
location / {
    root /usr/share/nginx/html;
}
location /api/ {
    proxy_pass http://backend-service:8080/api/;
}
```

## Hint 4 — Network Policy
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: database-access
spec:
  podSelector:
    matchLabels:
      app: postgres
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: backend
    ports:
    - port: 5432
```

## Hint 5 — Architecture README
Document: why you chose each image, how services communicate, what would you add for production (TLS, resource limits, HPA, backup strategy, secrets management).
