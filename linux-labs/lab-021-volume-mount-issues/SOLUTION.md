# Solution Walkthrough — Volume Mount Issues

## The Problem

A database container is running, but its data directory (`/data`) is empty — the customer records that should be there are missing. The data isn't lost, though. It's sitting safely inside a Docker **named volume** called `db-data`. The problem is that the container was started **without mounting that volume**.

When the container was created (with `docker run`), nobody included the `-v db-data:/data` flag. So the container created its own empty `/data` directory inside the container's writable layer, and the real data sitting in the `db-data` volume is orphaned — it exists but isn't accessible to any container.

This is a very common production mistake: someone restarts or recreates a container and forgets to include the volume mount, making it look like all the data has vanished.

## Thought Process

When data appears to be missing from a container, an experienced engineer checks:

1. **Is the data actually gone, or just unmounted?** Run `docker volume ls` to see if any named volumes exist. Then `docker volume inspect db-data` to see its details.
2. **Does the container have any volumes mounted?** `docker inspect database --format '{{json .Mounts}}'` shows what volumes are attached to the running container. If `Mounts` is empty or doesn't include the expected volume, that's the problem.
3. **Verify the data is in the volume** — you can peek inside a volume by running a temporary container: `docker run --rm -v db-data:/data alpine cat /data/customers.db`
4. **Recreate the container with the volume** — remove the current container and start a new one with `-v db-data:/data`.

The critical distinction is between data stored inside the container (ephemeral, lost when container is removed) and data stored in a Docker volume (persistent, survives container removal).

## Step-by-Step Solution

### Step 1: Check the container's current mounts

```bash
docker inspect database --format '{{json .Mounts}}'
```

**What this does:** Shows all volumes and bind mounts attached to the running container. You'll see `[]` (an empty list) — confirming that no volumes are mounted. The `/data` directory inside the container is just a regular directory in the container's writable layer, not backed by a persistent volume.

### Step 2: Check if the volume exists

```bash
docker volume ls
```

**What this does:** Lists all Docker volumes on the system. You should see `db-data` in the list — the volume exists and (presumably) contains the data. It's just not connected to any container.

### Step 3: Peek inside the volume to verify the data is there

```bash
docker run --rm -v db-data:/data alpine cat /data/customers.db
```

**What this does:** Creates a temporary Alpine container, mounts the `db-data` volume to `/data`, reads the file, and then removes itself (`--rm`). You should see the customer records (Alice, Bob, Charlie), proving the data is safe inside the volume.

### Step 4: Stop and remove the current container

```bash
docker rm -f database
```

**What this does:** Removes the running database container. The `-f` flag forces removal of a running container (it stops it first). This is safe because the container doesn't have any important data — the real data is in the volume.

### Step 5: Start a new container with the volume mounted

```bash
docker run -d --name database -v db-data:/data \
    python:3.11-slim python3 -c "
import time, os
os.makedirs('/data', exist_ok=True)
while True:
    time.sleep(60)
"
```

**What this does:** Creates a new container with the `db-data` volume properly mounted at `/data`. Here's what each flag means:
- `-d` — run in detached mode (background)
- `--name database` — name the container "database"
- `-v db-data:/data` — mount the named volume `db-data` to `/data` inside the container

The `-v db-data:/data` flag is the key fix. It tells Docker to connect the `db-data` volume to the `/data` path inside the container, making the customer records accessible.

### Step 6: Verify the data is accessible

```bash
docker exec database cat /data/customers.db
```

**What this does:** Reads the customer database file from inside the running container. You should see all the customer records — confirming the volume is properly mounted and the data is accessible.

### Step 7: Verify the volume mount is persistent

```bash
docker restart database
docker exec database cat /data/customers.db
```

**What this does:** Restarts the container and checks the data again. The data should still be there after the restart, proving that named volumes persist across container restarts. This is the whole point of volumes — data survives container lifecycle events.

### Step 8: Confirm the volume mount in container inspection

```bash
docker inspect database --format '{{range .Mounts}}{{.Name}} -> {{.Destination}}{{end}}'
```

**What this does:** Shows the volume mounts for the container. You should see `db-data -> /data`, confirming the named volume is properly attached.

## Docker Lab vs Real Life

- **Docker Compose volumes:** In production, you'd define volumes in a `docker-compose.yml` file, which ensures the volume is always mounted when the service starts. You can't accidentally forget the `-v` flag because it's codified in the Compose file:
  ```yaml
  services:
    database:
      volumes:
        - db-data:/data
  volumes:
    db-data:
  ```
- **Volume backup:** In production, you'd back up named volumes regularly. You can back up a volume by running: `docker run --rm -v db-data:/data -v $(pwd):/backup alpine tar czf /backup/db-backup.tar.gz /data`
- **Database containers:** Real database containers (PostgreSQL, MySQL, MongoDB) always require volume mounts for their data directories. Running a database without a volume means all data is lost when the container is removed.
- **Volume drivers:** Docker supports different volume drivers for different storage backends. The default `local` driver stores data on the host filesystem. In production, you might use drivers for NFS, AWS EBS, or other networked storage.
- **Kubernetes Persistent Volumes:** In Kubernetes, the equivalent concept is PersistentVolumeClaims (PVCs), which provide persistent storage for pods. The concept is the same — storage that outlives the individual container/pod.

## Key Concepts Learned

- **Docker volumes are separate from containers** — volumes persist even when no container is using them. Data in a volume survives container removal, recreation, and restarts.
- **Forgetting `-v` is a common source of "data loss"** — the data isn't lost, just not mounted. Always check `docker volume ls` before panicking.
- **`docker inspect` shows what's mounted** — the `Mounts` section tells you exactly which volumes are connected to a container
- **Named volumes vs. container storage** — data written to a directory without a volume mount lives in the container's writable layer and is lost when the container is removed. Named volumes persist independently.
- **Container recreation requires re-specifying volumes** — when you `docker rm` and `docker run` a new container, you must include all the `-v` flags again. The new container doesn't inherit mounts from the old one.

## Common Mistakes

- **Panicking and assuming data is lost** — the most important thing is to check `docker volume ls` first. The data is almost always still in the volume.
- **Using anonymous volumes instead of named volumes** — if you use `-v /data` without a name (anonymous volume), Docker creates a volume with a random hash name. These are hard to find and easy to accidentally remove with `docker volume prune`.
- **Running `docker volume prune`** — this command removes all unused volumes. If your container was stopped and the volume was "unused," the data would actually be deleted. Be very careful with this command in production.
- **Not including `-v` when recreating a container** — this is the exact mistake this lab simulates. When automating container creation, always define volumes in Docker Compose or scripts so they can't be forgotten.
- **Confusing volumes with bind mounts** — `-v db-data:/data` (named volume) and `-v /host/path:/data` (bind mount) look similar but behave differently. Named volumes are managed by Docker and portable. Bind mounts link to specific host directories and are tied to the host's filesystem.
