#!/bin/bash
# =============================================================================
# Fault Injection: Docker Networking Broken
# Creates two containers on separate networks so they can't communicate
# =============================================================================

# Clean up any previous run
docker rm -f backend-api frontend-web 2>/dev/null || true
docker network rm frontend-net backend-net 2>/dev/null || true

# Build a frontend image that includes curl for testing
# This gets cached after the first build so subsequent lab starts are fast
cat > /tmp/frontend.Dockerfile << 'EOF'
FROM python:3.11-slim
RUN apt-get update -qq && apt-get install -y -qq curl iputils-ping >/dev/null 2>&1 \
    && rm -rf /var/lib/apt/lists/*
CMD ["tail", "-f", "/dev/null"]
EOF
docker build -q -t lab-frontend -f /tmp/frontend.Dockerfile /tmp/ >/dev/null 2>&1

# Create two separate networks (this is the problem)
docker network create frontend-net 2>/dev/null || true
docker network create backend-net 2>/dev/null || true

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
" >/dev/null 2>&1

# Start frontend on frontend-net only (can't reach backend)
docker run -d --name frontend-web --network frontend-net \
    lab-frontend >/dev/null 2>&1

echo "Docker networking faults injected."
echo "frontend-web is on frontend-net"
echo "backend-api is on backend-net"
echo "They cannot communicate."
