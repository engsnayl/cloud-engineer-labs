Title: Service Won't Start — Port Already in Use
Difficulty: ⭐ (Beginner)
Time: 8-10 minutes
Category: Networking / Processes
Skills: ss, lsof, kill, netstat, process management

## Scenario

The new API service won't start because its port is already in use. Something else is bound to port 8080 and the service can't start.

> **INCIDENT-5412**: New API deployment failed — port 8080 already in use. Error: "bind: address already in use". Need to identify what's occupying the port and resolve the conflict.

Find what's using port 8080 and resolve the conflict.

## Objectives

1. Identify what process is using port 8080
2. Determine if it's a legitimate process or something stale
3. Free up port 8080
4. Start the actual API service
5. Verify it's responding

## Validation Criteria

- The stale process is no longer running
- The API service (python3 api.py) is running on port 8080
- `curl localhost:8080` returns HTTP 200
- No port conflicts exist

## What You're Practising

Port conflicts are one of the most common deployment issues. Knowing how to quickly find what's using a port and resolve the conflict is a basic but essential skill.
