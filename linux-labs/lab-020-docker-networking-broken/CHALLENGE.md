Title: Containers Can't Talk — Docker Network Issues
Difficulty: ⭐⭐ (Intermediate)
Time: 12-15 minutes
Category: Docker / Networking
Skills: docker network, docker inspect, container DNS, bridge networks

## Scenario

A multi-container application has a web frontend that should connect to an API backend, but the frontend can't reach the backend. The application was recently migrated from docker-compose to standalone containers and the networking was set up manually — badly.

> **INCIDENT-5545**: Frontend container can't reach backend-api container. DNS resolution failing between containers. Network team set up the containers on separate Docker networks by mistake. Both containers are running but can't communicate.

Fix the Docker networking so the frontend can reach the backend API.

## Objectives

1. Identify what Docker networks exist and which containers are on which network
2. Understand why the containers can't communicate
3. Get both containers onto the same network
4. Verify the frontend can reach the backend API by hostname
5. Confirm the API responds correctly

## Important: How This Lab Works

This is a **Docker lab**. The lab container is your workstation — it has Docker access via the mounted socket. The broken environment is two *other* containers (frontend-web and backend-api) that were started on separate networks.

- **Your Pi** (`engsnayl@pi:~$`) — `lab start`, `lab validate`, `lab stop`
- **Lab container** (`root@<hex>:/#`) — where you run `docker network`, `docker inspect`, etc.

## What You're Practising

Docker networking is fundamental to running microservices. In Kubernetes, pods communicate over a flat network, but in standalone Docker you need to explicitly manage networks. Understanding bridge networks, DNS resolution between containers, and network isolation is critical for container orchestration.
