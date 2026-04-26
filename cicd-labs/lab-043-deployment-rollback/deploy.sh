#!/bin/bash
# Production deployment script

echo "Deploying version: latest"

docker stop app 2>/dev/null
docker rm app 2>/dev/null
docker pull myapp:latest
docker run -d --name app -p 8080:8080 myapp:latest

echo "Deployed!"
