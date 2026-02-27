#!/bin/bash
# =============================================================================
# Fault Injection: Container Won't Start
# Creates a broken Docker image in a sub-directory
# =============================================================================

mkdir -p /opt/payment-service

# Create the application
cat > /opt/payment-service/app.py << 'PYEOF'
from http.server import HTTPServer, BaseHTTPRequestHandler
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b'Payment Service OK')
    def log_message(self, format, *args): pass
print("Payment service starting on port 5000...")
HTTPServer(('0.0.0.0', 5000), H).serve_forever()
PYEOF

# Create a broken Dockerfile
cat > /opt/payment-service/Dockerfile << 'DEOF'
FROM python:3.11-slim

RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Fault 1: Copy wrong filename
COPY application.py .

# Fault 2: Wrong entrypoint
ENTRYPOINT ["python3", "server.py"]
DEOF

echo "Docker build faults injected."
