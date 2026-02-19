#!/bin/bash
# Current deployment script — no rollback capability

# BUG 1: No health check after deploy
# BUG 2: No way to rollback
# BUG 3: No deployment versioning

echo "Deploying version: latest"

# Just overwrites the running container
docker stop app 2>/dev/null
docker rm app 2>/dev/null
docker pull myapp:latest
docker run -d --name app -p 80:8080 myapp:latest

echo "Deployed!"
