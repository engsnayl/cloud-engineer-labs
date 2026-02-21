Title: Compose Chaos — Multi-Container App Broken
Difficulty: ⭐⭐⭐ (Advanced)
Time: 15-20 minutes
Category: Docker / Compose
Skills: docker-compose, service dependencies, health checks, environment variables

## Scenario

A three-tier application (web → api → database) was set up with Docker Compose but nothing works. The compose file has multiple issues preventing the services from working together.

> **INCIDENT-5660**: Full application stack failing. Docker Compose brings up containers but they can't communicate. Health checks failing on all services. Compose file was written by a junior developer.

Fix the Docker Compose configuration so all three services work together.

## Objectives

1. Fix the `docker-compose.yml` — service dependencies, startup order, and connection strings
2. All three services must be running
3. The web service must respond on port 80
4. The API service must respond on port 5000

## What You're Practising

Docker Compose is the standard for local multi-container development and testing. Understanding service dependencies, networking, environment variables, and health checks is essential for container orchestration.
