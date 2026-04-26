#!/bin/bash
# setup.sh — prepare the lab environment
# Run this once after cd-ing into the lab directory.
#
# This builds three versions of a tiny web app and starts the "currently
# deployed" container, so the lab mirrors arriving at a real production
# system that already has something running.

set -e

echo "Setting up Lab 043 environment..."
echo ""

# Build a tiny Flask app with a /health endpoint
mkdir -p app
cat > app/app.py << 'EOF'
from flask import Flask
import os

app = Flask(__name__)
VERSION = os.environ.get("APP_VERSION", "unknown")
HEALTHY = os.environ.get("APP_HEALTHY", "true").lower() == "true"

@app.route("/")
def index():
    return f"myapp version {VERSION}\n"

@app.route("/health")
def health():
    if HEALTHY:
        return {"status": "ok", "version": VERSION}, 200
    return {"status": "unhealthy", "version": VERSION}, 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
EOF

cat > app/requirements.txt << 'EOF'
flask==3.0.0
EOF

# Dockerfile — healthy by default; we override APP_HEALTHY=false at run time
# to simulate the bad version, so we only build one image
cat > app/Dockerfile << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
ENV APP_VERSION=unknown
ENV APP_HEALTHY=true
EXPOSE 8080
CMD ["python", "app.py"]
EOF

echo "Building myapp:v1.0.0..."
docker build -t myapp:v1.0.0 ./app

echo "Tagging myapp:latest and myapp:v-bad..."
docker tag myapp:v1.0.0 myapp:latest
docker tag myapp:v1.0.0 myapp:v-bad

# Start the "currently deployed" container, exactly as the existing
# (broken) deploy.sh would have done it
echo ""
echo "Starting the currently-running container (myapp:latest)..."
docker stop app 2>/dev/null || true
docker rm app 2>/dev/null || true
docker run -d --name app -p 8080:8080 \
    -e APP_VERSION=v1.0.0 \
    -e APP_HEALTHY=true \
    myapp:latest

sleep 2

echo ""
echo "Setup complete. Current state:"
echo ""
docker ps --filter "name=app" --format "  {{.Names}}  →  {{.Image}}  ({{.Status}})"
echo ""
echo "App should be reachable at http://localhost:8080"
echo "Health endpoint at      http://localhost:8080/health"
echo ""
