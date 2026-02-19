#!/bin/bash
# =============================================================================
# Fault Injection: Docker Networking Broken
# Sets up containers on separate networks
# =============================================================================

# This lab needs docker-in-docker or socket mount
# Create helper scripts for the student

cat > /opt/setup-broken-network.sh << 'SEOF'
#!/bin/bash
# Create two separate networks (the problem)
docker network create frontend-net 2>/dev/null || true
docker network create backend-net 2>/dev/null || true

# Stop any existing containers
docker rm -f backend-api frontend-web 2>/dev/null || true

# Start backend on backend-net only
docker run -d --name backend-api --network backend-net \
    python:3.11-slim python3 -c "
from http.server import HTTPServer, BaseHTTPRequestHandler
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'{\"status\": \"healthy\", \"service\": \"backend-api\"}')
    def log_message(self, format, *args): pass
print('Backend API running on port 3000')
HTTPServer(('0.0.0.0', 3000), H).serve_forever()
"

# Start frontend on frontend-net only (can't reach backend)
docker run -d --name frontend-web --network frontend-net \
    python:3.11-slim python3 -c "
import time
while True:
    time.sleep(60)
"

echo "Broken network setup complete."
echo "frontend-web is on frontend-net"
echo "backend-api is on backend-net"
echo "They cannot communicate!"
SEOF
chmod +x /opt/setup-broken-network.sh

echo "Docker networking faults prepared. Run /opt/setup-broken-network.sh to create the broken environment."
