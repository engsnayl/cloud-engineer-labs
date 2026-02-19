#!/bin/bash
# =============================================================================
# Fault Injection: Compose Orchestration Broken
# =============================================================================

mkdir -p /opt/fullstack-app

# Create a broken docker-compose.yml
cat > /opt/fullstack-app/docker-compose.yml << 'EOF'
version: "3.8"
services:
  web:
    image: nginx:alpine
    ports:
      - "80:80"
    # Fault 1: depends_on references wrong service name
    depends_on:
      - backend
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf

  api:
    image: python:3.11-slim
    command: python3 /app/api.py
    # Fault 2: Missing volume mount for app code
    environment:
      # Fault 3: Wrong database host
      - DB_HOST=database
      - DB_PORT=5432

  db:
    image: postgres:15-alpine
    environment:
      # Fault 4: Missing required POSTGRES_PASSWORD
      - POSTGRES_USER=appuser
      - POSTGRES_DB=appdb
EOF

# Create the API
mkdir -p /opt/fullstack-app/app
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

# Create nginx config that proxies to API
cat > /opt/fullstack-app/nginx.conf << 'EOF'
server {
    listen 80;
    location / {
        proxy_pass http://api:5000;
    }
}
EOF

echo "Compose orchestration faults injected."
echo "cd /opt/fullstack-app && docker compose up to see the failures."
