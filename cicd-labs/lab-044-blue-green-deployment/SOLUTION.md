# Solution Walkthrough — Blue-Green Deployment

## The Problem

Deployments cause 10-30 seconds of downtime because the application is stopped before the new version starts. The team needs zero-downtime deployments using a blue-green strategy. The `switch.sh` script is a stub — it says "TODO: Implement blue/green switching" and doesn't do anything.

The infrastructure is already in place:
- **app-blue** runs on port 8001 (current live version)
- **app-green** runs on port 8002 (staging/next version)
- **nginx router** on port 80 proxies traffic to whichever environment is active
- **nginx.conf** is hardcoded to route to `app-blue` only

The task is to create `switch.sh` that switches traffic between blue and green environments with zero downtime.

## Thought Process

When implementing blue-green deployments, an experienced engineer plans:

1. **Determine current active environment** — read the nginx config to see which upstream is active (blue or green).
2. **Deploy to the inactive environment** — the new version goes to the environment that isn't receiving traffic. Users aren't affected.
3. **Health check the inactive environment** — before switching traffic, verify the new version is healthy. Don't switch to a broken deployment.
4. **Switch traffic** — update the nginx config to point to the newly deployed environment and reload nginx. `nginx -s reload` is graceful — it finishes existing connections before switching.
5. **Keep the old environment running** — if something goes wrong after switching, you can instantly switch back. The old version is still running and warm.

## Step-by-Step Solution

### Step 1: Detect the current active environment

Create `switch.sh` starting with environment detection.

```bash
#!/bin/bash
set -e

# Determine which environment is currently active
if grep -q "app-blue" /etc/nginx/conf.d/default.conf 2>/dev/null || \
   grep -q "app-blue" nginx.conf 2>/dev/null; then
    CURRENT="blue"
    TARGET="green"
    TARGET_PORT=8002
else
    CURRENT="green"
    TARGET="blue"
    TARGET_PORT=8001
fi

echo "Current active: $CURRENT"
echo "Switching to: $TARGET"
```

**What this does:** The script reads the nginx configuration to determine which environment is currently receiving traffic. If the config contains `app-blue`, blue is active and green is the target (and vice versa). This makes the script idempotent — run it once to switch blue→green, run it again to switch green→blue.

### Step 2: Health check the target environment

```bash
# Health check the target environment before switching
echo "Health checking $TARGET environment..."
MAX_RETRIES=10
HEALTHY=false

for i in $(seq 1 $MAX_RETRIES); do
    if curl -sf "http://localhost:$TARGET_PORT/health" > /dev/null 2>&1 || \
       curl -sf "http://localhost:$TARGET_PORT/" > /dev/null 2>&1; then
        HEALTHY=true
        echo "Health check passed for $TARGET (attempt $i)"
        break
    fi
    echo "Attempt $i/$MAX_RETRIES — waiting for $TARGET..."
    sleep 2
done

if [ "$HEALTHY" != "true" ]; then
    echo "ERROR: $TARGET environment is not healthy. Aborting switch."
    exit 1
fi
```

**What this does:** Before switching any traffic, we verify the target environment is actually working. If the green deployment crashed or is still starting up, we don't switch — users continue to be served by the healthy blue environment. The retry loop gives the application time to start. If health checks fail after all retries, the script aborts and traffic stays on the current environment.

### Step 3: Update the nginx configuration

```bash
# Update nginx to point to the target environment
if [ "$TARGET" = "green" ]; then
    cat > /etc/nginx/conf.d/default.conf << 'EOF'
upstream app {
    server app-green:8080;
}

server {
    listen 80;
    location / {
        proxy_pass http://app;
    }
}
EOF
else
    cat > /etc/nginx/conf.d/default.conf << 'EOF'
upstream app {
    server app-blue:8080;
}

server {
    listen 80;
    location / {
        proxy_pass http://app;
    }
}
EOF
fi
```

**What this does:** Writes a new nginx config that points the `app` upstream to the target environment. This doesn't affect traffic yet — nginx is still using the old config in memory. The actual switch happens in the next step when we reload.

### Step 4: Reload nginx for zero-downtime switch

```bash
# Graceful reload — zero dropped connections
nginx -s reload
echo "Traffic switched from $CURRENT to $TARGET"
echo "Previous environment ($CURRENT) still running for quick rollback"
```

**What this does:** `nginx -s reload` sends a signal to the nginx master process to reload the configuration. The master starts new worker processes with the new config while existing workers finish handling their current connections. This means zero dropped connections — requests in flight complete on the old backend, new requests go to the new backend. It's instantaneous from the user's perspective.

### Step 5: Make the script executable

```bash
chmod +x switch.sh
```

### Step 6: The complete switch.sh

```bash
#!/bin/bash
set -e

# Determine current active environment
if grep -q "app-blue" /etc/nginx/conf.d/default.conf 2>/dev/null || \
   grep -q "app-blue" nginx.conf 2>/dev/null; then
    CURRENT="blue"
    TARGET="green"
    TARGET_PORT=8002
else
    CURRENT="green"
    TARGET="blue"
    TARGET_PORT=8001
fi

echo "Current: $CURRENT → Switching to: $TARGET"

# Health check target
HEALTHY=false
for i in $(seq 1 10); do
    if curl -sf "http://localhost:$TARGET_PORT/" > /dev/null 2>&1; then
        HEALTHY=true
        break
    fi
    sleep 2
done

if [ "$HEALTHY" != "true" ]; then
    echo "ERROR: $TARGET not healthy. Aborting."
    exit 1
fi

# Update nginx config
if [ "$TARGET" = "green" ]; then
    sed -i 's/app-blue/app-green/g' /etc/nginx/conf.d/default.conf
else
    sed -i 's/app-green/app-blue/g' /etc/nginx/conf.d/default.conf
fi

# Reload nginx — zero downtime
nginx -s reload
echo "Switched to $TARGET. Rollback: run this script again."
```

### Step 7: Validate

```bash
# Make executable
chmod +x switch.sh

# Run it
./switch.sh

# Verify traffic goes to the new environment
curl http://localhost/
```

## Docker Lab vs Real Life

- **Load balancer switching:** In production, the switch happens at the load balancer level (ALB, NLB, or Route 53 weighted routing) rather than nginx. AWS CodeDeploy automates blue-green switching with ALB target groups.
- **DNS-based blue-green:** Some teams use Route 53 weighted records — blue gets 100% weight, then gradually shift to green (canary) or switch instantly (blue-green).
- **Database migrations:** The hardest part of blue-green deployments is database schema changes. Both versions must work with the same database during the transition. Use backward-compatible migrations.
- **Warm-up period:** After switching, monitor error rates for 5-10 minutes. If the new version has issues under real traffic, switch back immediately.
- **Infrastructure cost:** True blue-green requires running two full environments simultaneously. In cloud environments, this doubles infrastructure cost during deployments. Some teams only spin up the green environment during deploys and tear it down after.

## Key Concepts Learned

- **Blue-green eliminates deployment downtime** — traffic switches instantly between two identical environments. No stop-start gap.
- **`nginx -s reload` is graceful** — existing connections finish on the old backend, new connections go to the new backend. Zero dropped requests.
- **Always health check before switching** — deploying a broken version to the inactive environment is safe. Switching traffic to it is not. The health check is the gate.
- **Keep the old environment running** — the fastest rollback is switching back. If the old environment is already running, rollback takes seconds instead of minutes.
- **The script is its own rollback** — running `switch.sh` toggles between blue and green. If green is bad, run it again to switch back to blue.

## Common Mistakes

- **Switching without health checking** — routing traffic to a broken environment causes an outage. Always verify the target is healthy before switching.
- **Stopping the old environment immediately** — if you shut down blue right after switching to green, you can't quickly roll back. Keep the old environment running for at least 30 minutes.
- **Not testing the rollback** — practice switching back. The rollback path should be tested just as thoroughly as the deployment path.
- **Database schema incompatibility** — if green requires a schema migration that breaks blue, you can't roll back. Always make schema changes backward-compatible.
- **Forgetting to reload nginx** — updating the config file does nothing until nginx reloads. The config and the reload are both required.
