# Solution Walkthrough: Part 1 — Database Layer

## Why Start Here?

The database is the **foundation** of the stack. It has no dependencies on other components, but the backend depends on it. Building bottom-up means we can test each layer in isolation before connecting the next one.

## Files in This Layer

| File | Purpose |
|------|---------|
| `k8s/postgres-secret.yaml` | Stores database credentials |
| `k8s/postgres-init-configmap.yaml` | SQL script that creates tables on first boot |
| `k8s/postgres-statefulset.yaml` | Runs the PostgreSQL pod with persistent storage |
| `k8s/postgres-service.yaml` | Gives the database a stable DNS name |

## Key Decisions Explained

### Why a StatefulSet Instead of a Deployment?

Deployments are designed for **stateless** workloads. When a Deployment pod dies, the replacement gets a random name and starts with a clean slate — no leftover data. That's perfect for web servers, but catastrophic for a database.

StatefulSets solve this with:
- **Stable pod names** — Always `postgres-0`, never `postgres-7xk2f`
- **Stable storage** — The PersistentVolumeClaim sticks around even when the pod is deleted
- **Ordered operations** — Pods start up and shut down in a predictable sequence

### Why a Headless Service (clusterIP: None)?

Normal Services create a virtual IP that load-balances traffic. But you wouldn't want to load-balance database queries across multiple database instances unless you've set up replication (read replicas, etc.).

A headless Service skips the virtual IP and creates direct DNS entries for each pod:
```
postgres-0.postgres.multi-tier-app.svc.cluster.local
```

Since we only have one replica, the backend connects to `postgres` and Kubernetes DNS resolves it directly to our single pod.

### Why subPath for the Volume Mount?

In the StatefulSet, we set `PGDATA` to `/var/lib/postgresql/data/pgdata` (a subdirectory). This is because:

1. The PersistentVolume's root directory might contain filesystem artifacts like `lost+found`
2. PostgreSQL requires the data directory to be completely empty on first init
3. Using a subdirectory avoids this conflict — `lost+found` stays at the root, and PostgreSQL gets a clean `pgdata/` subdirectory

This is a **very common gotcha** that causes PostgreSQL pods to crash on startup with confusing errors.

### Why base64 in Secrets?

Kubernetes Secrets store values as base64-encoded strings. This is **not encryption** — anyone can decode base64. It's just encoding that lets you store binary data safely in YAML.

The real security comes from:
- RBAC controls on who can read Secrets
- Encryption at rest (configurable at the cluster level)
- In production: external secret managers (Vault, AWS Secrets Manager)

Quick reference for our values:
```bash
echo -n "postgres"           | base64    # cG9zdGdyZXM=
echo -n "securepassword123"  | base64    # c2VjdXJlcGFzc3dvcmQxMjM=
echo -n "multitierdb"        | base64    # bXVsdGl0aWVyZGI=
```

### How the Init Script Works

The official PostgreSQL Docker image has a built-in mechanism: on **first boot only** (when the data directory is empty), it executes all `.sql` and `.sh` files found in `/docker-entrypoint-initdb.d/` in alphabetical order.

We exploit this by:
1. Putting our SQL in a ConfigMap (key: `init.sql`)
2. Mounting that ConfigMap as a volume at `/docker-entrypoint-initdb.d/`
3. PostgreSQL finds `init.sql` and runs it automatically

After the first boot, the data directory is no longer empty, so the init script is skipped on restarts.

## Testing This Layer

After deploying, you can verify the database is working:

```bash
# Check the pod is running
kubectl -n multi-tier-app get pods -l app=postgres

# Check the logs for successful startup
kubectl -n multi-tier-app logs postgres-0

# Connect to the database directly
kubectl -n multi-tier-app exec -it postgres-0 -- psql -U postgres -d multitierdb

# Inside psql, verify the table and seed data exist:
\dt                          -- List tables
SELECT * FROM items;         -- Show seed data
\q                           -- Quit
```

## Common Issues

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Pod stuck in `CrashLoopBackOff` | `lost+found` in data directory | Ensure `PGDATA` points to a subdirectory |
| Init script didn't run | Data directory not empty (previous PVC) | Delete the PVC and let it recreate |
| Can't connect from backend | Secret values don't match ConfigMap | Decode and verify all base64 values match |
| Pod stuck in `Pending` | No PersistentVolume available | Check storage class or provisioner |
