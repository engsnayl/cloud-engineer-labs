Title: Containers Can't Talk — Docker Network Issues
Difficulty: ⭐⭐ (Intermediate)
Time: 12-15 minutes
Category: Docker / Networking
Skills: docker network, container linking, DNS resolution, bridge networks

## Scenario

A multi-container application has a web frontend that should connect to an API backend, but the frontend can't reach the backend. They seem to be on different Docker networks.

> **INCIDENT-5545**: Frontend container can't reach backend-api container. DNS resolution failing between containers. Application was recently migrated from docker-compose to standalone containers and networking was set up manually.

Fix the Docker networking so the containers can communicate.

## Objectives

1. Get both `backend-api` and `frontend-web` containers running
2. Connect both containers to the same Docker network
3. Containers must communicate by hostname — `frontend-web` must be able to reach `backend-api` on port 3000

## What You're Practising

Docker networking is fundamental to running microservices. Understanding bridge networks, DNS resolution between containers, and network isolation is critical for container orchestration.
