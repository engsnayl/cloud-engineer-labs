#!/bin/bash
# Lab 044 — One-time setup
# Builds placeholder myapp:v1 and myapp:v2 images locally so docker compose up
# can pull from the local image cache. In real life these images would come
# from a CI pipeline that built and pushed them to a registry. Run this once,
# then forget it exists — the lab itself starts when you cat docker-compose.yml.

set -e

echo "Setting up lab environment..."
echo ""

# Working directory for build context — cleaned up at the end
BUILD_DIR=$(mktemp -d)
trap "rm -rf $BUILD_DIR" EXIT

# ---------- myapp:v1 (the "blue" version) ----------
mkdir -p "$BUILD_DIR/v1"
cat > "$BUILD_DIR/v1/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head><title>myapp v1</title></head>
<body style="font-family: sans-serif; background:#1e3a8a; color:white; text-align:center; padding:4em;">
  <h1>myapp v1 — BLUE</h1>
  <p>This is the v1 release.</p>
</body>
</html>
EOF

cat > "$BUILD_DIR/v1/Dockerfile" << 'EOF'
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/index.html
RUN sed -i 's/listen       80;/listen       8080;/' /etc/nginx/conf.d/default.conf
EXPOSE 8080
EOF

echo "Building myapp:v1..."
docker build -q -t myapp:v1 "$BUILD_DIR/v1" > /dev/null

# ---------- myapp:v2 (the "green" version) ----------
mkdir -p "$BUILD_DIR/v2"
cat > "$BUILD_DIR/v2/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<head><title>myapp v2</title></head>
<body style="font-family: sans-serif; background:#065f46; color:white; text-align:center; padding:4em;">
  <h1>myapp v2 — GREEN</h1>
  <p>This is the v2 release.</p>
</body>
</html>
EOF

cat > "$BUILD_DIR/v2/Dockerfile" << 'EOF'
FROM nginx:alpine
COPY index.html /usr/share/nginx/html/index.html
RUN sed -i 's/listen       80;/listen       8080;/' /etc/nginx/conf.d/default.conf
EXPOSE 8080
EOF

echo "Building myapp:v2..."
docker build -q -t myapp:v2 "$BUILD_DIR/v2" > /dev/null

echo ""
echo "✅  Setup complete. Images built:"
docker images --format "    {{.Repository}}:{{.Tag}}  ({{.Size}})" | grep '^    myapp:'
echo ""
echo "You can now start the lab. Begin by exploring the working directory."
