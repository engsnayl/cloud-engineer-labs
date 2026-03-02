#!/bin/bash
# Start a local Docker registry
docker run -d --name registry -p 5000:5000 registry:2 2>/dev/null || true

# Create a simple app image
mkdir -p /opt/myapp
cat > /opt/myapp/Dockerfile << 'DEOF'
FROM python:3.11-slim
RUN echo 'from http.server import HTTPServer, BaseHTTPRequestHandler\nclass H(BaseHTTPRequestHandler):\n    def do_GET(self):\n        self.send_response(200)\n        self.end_headers()\n        self.wfile.write(b"Registry App OK")\nHTTPServer(("0.0.0.0",8080),H).serve_forever()' > /app.py
CMD ["python3", "/app.py"]
DEOF

# Build with wrong tag (not pointing to local registry)
docker build -t myapp:latest /opt/myapp/ 2>/dev/null

# Fault: Image is tagged as 'myapp:latest' but needs to be 'localhost:5000/myapp:latest'
# Student needs to retag and push

echo "Registry faults injected."
echo "Image 'myapp:latest' exists but can't be pushed/pulled from registry."
echo "Local registry running on localhost:5000"
