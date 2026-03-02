# Solution Walkthrough — Deployment Rollback Strategy

## The Problem

The deployment script (`deploy.sh`) deploys new versions without any safety net. When a bad version is deployed, there's no way to recover automatically. The script has **three issues**:

1. **No health check** — the script deploys and walks away. If the new version crashes, nobody knows until users report it. There's no automated verification that the deployment succeeded.
2. **No rollback mechanism** — when a bad deploy happens, there's no way to automatically revert to the previous working version. Engineers must manually figure out what was running before and redeploy it.
3. **No version tagging** — the script always deploys the `latest` tag. There's no way to know what version is currently running, what version was running before, or to deploy a specific version.

## Thought Process

When a deployment process is unreliable, an experienced engineer checks:

1. **Health checks** — after deploying, the script should verify the application is actually working. Hit the health endpoint, check the response, retry a few times before declaring failure.
2. **Rollback capability** — before deploying the new version, record what's currently running. If the health check fails, automatically redeploy the previous version.
3. **Version management** — use explicit version tags (not `latest`). Accept version as a parameter so you can deploy or rollback to any specific version.
4. **Idempotency** — running the script twice with the same version should be safe. Running it with a previous version should work as a manual rollback.

## Step-by-Step Solution

### Step 1: Accept a version parameter

The script should require a version number instead of always using `latest`.

```bash
#!/bin/bash
set -e

VERSION=${1:?Usage: ./deploy.sh <version>}
APP_NAME="myapp"
HEALTH_URL="http://localhost:8080/health"
MAX_RETRIES=10
RETRY_INTERVAL=3
```

**What this does:** `${1:?Usage: ...}` takes the first command-line argument as the version. If no argument is provided, the script exits with a usage message. This ensures every deployment is tied to a specific, traceable version. You can run `./deploy.sh v1.2.3` to deploy a specific version or `./deploy.sh v1.2.2` to roll back to a previous one.

### Step 2: Record the current version before deploying

```bash
# Save the current version for rollback
PREVIOUS=$(docker inspect --format='{{.Config.Image}}' "$APP_NAME" 2>/dev/null || echo "none")
echo "Current version: $PREVIOUS"
echo "Deploying version: $APP_NAME:$VERSION"
```

**What this does:** Before touching anything, the script records what's currently running by inspecting the existing container's image tag. If the deployment fails, this saved value is the rollback target. The `|| echo "none"` handles the case where no container exists yet (first deployment).

### Step 3: Deploy the new version

```bash
# Stop the old container
docker stop "$APP_NAME" 2>/dev/null || true
docker rm "$APP_NAME" 2>/dev/null || true

# Start the new version
docker run -d --name "$APP_NAME" -p 8080:8080 "$APP_NAME:$VERSION"
echo "Started $APP_NAME:$VERSION"
```

**What this does:** Stops the existing container and starts the new version. The `|| true` ensures the script doesn't fail if there's no existing container to stop (first deployment or after a crash). The container is named consistently so we can always find and manage it.

### Step 4: Add a health check with retries

```bash
# Health check with retries
echo "Running health checks..."
HEALTHY=false
for i in $(seq 1 $MAX_RETRIES); do
    if curl -sf "$HEALTH_URL" > /dev/null 2>&1; then
        HEALTHY=true
        echo "Health check passed on attempt $i"
        break
    fi
    echo "Health check attempt $i/$MAX_RETRIES failed, retrying in ${RETRY_INTERVAL}s..."
    sleep "$RETRY_INTERVAL"
done
```

**What this does:** After deploying, the script hits the health endpoint up to 10 times with 3-second intervals. `curl -sf` silently fails on HTTP errors (`-f`) and suppresses output (`-s`). The application might need a few seconds to start up, so we retry rather than failing immediately. If the health check passes on any attempt, we declare success.

### Step 5: Rollback on failure

```bash
if [ "$HEALTHY" = true ]; then
    echo "Deployment successful: $APP_NAME:$VERSION"
else
    echo "ERROR: Health check failed after $MAX_RETRIES attempts"
    echo "Rolling back to $PREVIOUS..."

    # Rollback to previous version
    docker stop "$APP_NAME" 2>/dev/null || true
    docker rm "$APP_NAME" 2>/dev/null || true

    if [ "$PREVIOUS" != "none" ]; then
        docker run -d --name "$APP_NAME" -p 8080:8080 "$PREVIOUS"
        echo "Rolled back to $PREVIOUS"
    else
        echo "No previous version to rollback to"
    fi
    exit 1
fi
```

**What this does:** If the health check never passes, the script automatically rolls back to the previously recorded version. It stops the failing container, removes it, and starts the old version. The `exit 1` signals failure to the calling system (CI/CD pipeline, monitoring, etc.) so alerts can fire.

### Step 6: Validate

```bash
# Test the script
chmod +x deploy.sh

# Deploy a good version
./deploy.sh v1.0.0

# Deploy a bad version (should automatically rollback)
./deploy.sh v-bad

# Check what's running
docker inspect --format='{{.Config.Image}}' myapp
```

## Docker Lab vs Real Life

- **Blue-green deployments:** Instead of stopping the old container before starting the new one (which causes downtime), production systems run both simultaneously and switch traffic after the health check passes.
- **Container orchestration:** In Kubernetes or ECS, rolling updates and rollbacks are built-in. `kubectl rollout undo` or ECS deployment circuit breakers handle this automatically.
- **Deployment tracking:** Production systems log every deployment to a database or service (Datadog, PagerDuty, deploy tracker). This creates an audit trail of who deployed what, when, and whether it succeeded.
- **Canary deployments:** Instead of deploying to all instances at once, route 5% of traffic to the new version first. If error rates stay normal, gradually increase to 100%.
- **Feature flags:** Decouple deployments from releases. Deploy the code but keep the feature behind a flag. If something goes wrong, flip the flag instead of rolling back the entire deployment.

## Key Concepts Learned

- **Always health check after deploying** — a deployment isn't done until the application responds correctly. Use `curl` against the health endpoint with retries to account for startup time.
- **Record the previous version before deploying** — `docker inspect` captures the current image. Without this, rollback is impossible because you don't know what to roll back to.
- **Use explicit version tags** — `latest` is ambiguous and un-reproducible. Version tags like `v1.2.3` let you deploy, rollback, and audit specific releases.
- **Automatic rollback prevents extended outages** — if the health check fails, immediately restore the previous version. Manual rollback means minutes of downtime while an engineer responds.
- **Exit with non-zero on failure** — `exit 1` tells the CI/CD system the deployment failed, triggering alerts and preventing further pipeline steps.

## Common Mistakes

- **No health check at all** — deploying without verification is hoping for the best. Always verify the application is working after deployment.
- **Health check without retries** — applications need time to start. A single immediate health check almost always fails. Use a retry loop with appropriate delays.
- **Using `latest` tag exclusively** — `latest` is not a version. You can't rollback to `latest` because it changes with every build. Always tag images with specific versions.
- **Not saving the previous version** — if you don't know what was running before, you can't automatically roll back. Always inspect and save before deploying.
- **Rollback that doesn't get health-checked** — the rollback itself could fail. Production rollback scripts should also health-check the restored version.
