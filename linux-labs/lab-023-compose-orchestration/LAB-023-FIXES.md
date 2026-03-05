# Lab 023 — Setup Fixes Required

## Problems Found During Testing

When running this lab on the Pi, several setup issues prevented the solution from working even after fixing the four intended bugs. These are lab infrastructure problems, not part of the challenge.

---

## Fix 1: Port 80 conflicts with K3s Traefik

**Problem:** K3s runs Traefik as its ingress controller, which has iptables rules intercepting all traffic on port 80. When the Compose stack maps port 80, Traefik catches the request first and returns a plain text "404 page not found" before Docker's port mapping ever sees it.

**Fix:** Change the port mapping in the broken docker-compose.yml from `"80:80"` to `"8080:80"`. Update the solution file to use port 8080 throughout. Update validate.sh to check port 8080 instead of port 80.

In `inject-faults.sh`, change:
```yaml
    ports:
      - "8080:80"
```

In `validate.sh`, change:
```bash
curl -s http://localhost:8080 2>/dev/null | grep -q "ok"
```

---

## Fix 2: nginx.conf created as a directory on the host

**Problem:** The `/opt/fullstack-app` directory is bind-mounted between the Pi host and the lab container. When Docker sees a volume mount like `./nginx.conf:/etc/nginx/conf.d/default.conf` and `nginx.conf` doesn't exist on the host yet, Docker creates it as a directory by default. The inject-faults.sh creates it as a file inside the container, but the host already has a directory at that path.

**Fix:** The lab setup needs to create `nginx.conf` as a file on the Pi host before the lab container starts. Add to the lab setup:

```bash
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

## Fix 3: api.py not present on the Pi host

**Problem:** The inject-faults.sh creates `app/api.py` inside the lab container's filesystem, but the volume mount `./app:/app` in the fixed Compose file looks for the file on the Pi host. The `app/` directory exists on the Pi but is empty.

**Fix:** Add api.py creation to the same lab setup script:

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

## Fix 4: docker-compose-v2 not installed in the lab container

**Problem:** The lab container has Docker installed but not the Compose plugin. Running `docker compose up` fails with "unknown command."

**Fix:** Add to the lab container's Dockerfile:

```dockerfile
RUN apt-get update && apt-get install -y docker-compose-v2 && rm -rf /var/lib/apt/lists/*
```

---

## Fix 5: Validator uses curl but API container doesn't have it

**Problem:** The validate.sh runs `docker compose exec -T api curl -s http://localhost:5000`, but the `python:3.11-slim` image doesn't include curl. This check always fails.

**Fix:** Use Python instead of curl in validate.sh:

```bash
# Replace this line:
docker compose exec -T api curl -s http://localhost:5000 2>/dev/null | grep -q "ok"

# With this:
docker compose exec -T api python3 -c "import urllib.request; print(urllib.request.urlopen('http://localhost:5000').read().decode())" 2>/dev/null | grep -q "ok"
```

---

## Fix 6: Host Nginx can conflict with mapped port

**Problem:** If Nginx is running on the Pi host, it may occupy ports that conflict with the Compose stack.

**Fix:** Add to the lab setup script:

```bash
sudo systemctl stop nginx 2>/dev/null || true
```

---

## Summary of Changes Needed

| File | Change |
|------|--------|
| inject-faults.sh | Change port mapping from `"80:80"` to `"8080:80"` |
| Lab setup script | Create nginx.conf and api.py on Pi host before lab starts |
| Lab Dockerfile | Install docker-compose-v2 |
| validate.sh | Use port 8080 for web check; use python3 urllib instead of curl for API check |
| Lab setup script | Stop host Nginx if running |
