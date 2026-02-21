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

1. Identify and stop the stale process occupying port 8080
2. Start the API service (`/opt/api.py`) on port 8080
3. `curl localhost:8080` must return a successful response

## What You're Practising

Port conflicts are one of the most common deployment issues. Knowing how to quickly find what's using a port and resolve the conflict is a basic but essential skill.
