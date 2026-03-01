# Lab 023 — Setup Fixes Required

## Problems Found During Testing

When running this lab on the Pi, several setup issues prevented the solution from working even after fixing the four intended bugs. These are lab infrastructure problems, not part of the challenge.

---

## Fix 1: nginx.conf created as a directory on the host

**Problem:** The inject-faults.sh runs inside the lab container and creates `/opt/fullstack-app/nginx.conf` as a file. But `/opt/fullstack-app` is bind-mounted from the Pi host. When Docker (running on the Pi) tries to mount `./nginx.conf:/etc/nginx/conf.d/default.conf`, it sees a directory on the Pi instead of a file.

**Root cause:** The `docker-compose.yml` for the lab likely creates the `/opt/fullstack-app` directory on the Pi before the inject-faults script runs. Docker creates missing mount sources as directories by default.

**Fix:** The lab's own `docker-compose.yml` (the one that starts the lab container, not the broken one inside it) needs to ensure `nginx.conf` exists as a file on the Pi host before the lab container starts. Add to the lab setup:

```bash
# In the lab runner or setup script, before starting the lab container:
mkdir -p /opt/fullstack-app/app
cat > /opt/fullstack-app/nginx.conf << 'EOF'
server {
    listen 80;
    location / {
        proxy_pass http://api:5000;
    }
}
EOF
```

---

## Fix 2: api.py not present on the Pi host

**Problem:** The inject-faults.sh creates `/opt/fullstack-app/app/api.py` inside the container, but the `./app:/app` volume mount in the fixed docker-compose.yml looks for `./app/api.py` on the Pi host filesystem. The `app/` directory exists on the Pi but is empty.

**Fix:** Add `api.py` creation to the same lab setup script:

```bash
cat > /opt/fullstack-app/app/api.py << 'PYEOF'
from http.server import HTTPServer, BaseHTTPRequestHandler
import os
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        db_host = os.environ.get('DB_HOST', 'unknown')
        self.send_response(200)
        self.end_headers()
        self.wfile.write(f'{{"status":"ok","db_host":"{db_host}"}}'.encode())
    def log_message(self, format, *args): pass
print("API running on port 5000")
HTTPServer(('0.0.0.0', 5000), H).serve_forever()
PYEOF
```

---

## Fix 3: docker-compose-v2 not installed in the lab container

**Problem:** The lab container has Docker installed but not the Compose plugin. Running `docker compose up` fails with "unknown command".

**Fix:** Add to the lab container's Dockerfile:

```dockerfile
RUN apt-get update && apt-get install -y docker-compose-v2 && rm -rf /var/lib/apt/lists/*
```

---

## Fix 4: Validator uses curl but API container doesn't have it

**Problem:** The validate.sh runs `docker compose exec -T api curl -s http://localhost:5000`, but the `python:3.11-slim` image doesn't include curl. This check always fails.

**Fix — Option A (change the validator):** Use Python instead of curl in validate.sh:

```bash
# Replace this line:
docker compose exec -T api curl -s http://localhost:5000 2>/dev/null | grep -q "ok"

# With this:
docker compose exec -T api python3 -c "import urllib.request; print(urllib.request.urlopen('http://localhost:5000').read().decode())" 2>/dev/null | grep -q "ok"
```

**Fix — Option B (keep the validator, change the solution):** The solution would need to use a custom Dockerfile for the API that installs curl. This makes the lab more complex than intended.

**Recommendation:** Option A is cleaner — the validator should work with the standard solution.

---

## Fix 5: Host Nginx conflicts with port 80

**Problem:** If Nginx is running on the Pi host, it occupies port 80 and the Compose stack can't bind to it.

**Fix:** Add to the lab setup script:

```bash
sudo systemctl stop nginx 2>/dev/null || true
```

Or document in the challenge that students should check for port conflicts as part of troubleshooting.

---

## Summary of Changes Needed

| File | Change |
|------|--------|
| Lab setup script | Create nginx.conf and api.py on Pi host before lab starts |
| Lab Dockerfile | Install docker-compose-v2 |
| validate.sh | Use python3 urllib instead of curl for API check |
| Lab setup script | Stop host Nginx if running |
