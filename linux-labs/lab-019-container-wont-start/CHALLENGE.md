Title: Container Won't Start — Docker Troubleshooting
Difficulty: ⭐⭐ (Intermediate)
Time: 10-15 minutes
Category: Docker / Containers
Skills: docker logs, docker inspect, docker run, Dockerfile debugging

## Scenario

A developer pushed a new Docker image for the payment service but the container immediately exits when started. The image builds fine but won't run.

> **INCIDENT-5501**: Payment service container exits immediately on start. `docker ps -a` shows status "Exited (1)". The developer says "it works on my machine". Image builds without errors but container dies instantly.

Investigate the image, find the issues, and get the container running.

## Objectives

1. Check the container logs to see why it exited
2. Inspect the image configuration
3. Identify issues with the entrypoint/command
4. Fix the Dockerfile and rebuild
5. Verify the container stays running and responds

## Validation Criteria

- The payment-service container is running (not exited)
- `docker logs` shows no error messages
- The service responds on port 5000
- Container has been running for >5 seconds

## What You're Practising

Docker containers that won't start are the most common Docker debugging task. Understanding how to read container logs, inspect image configuration, and debug entrypoints is fundamental to container operations.
