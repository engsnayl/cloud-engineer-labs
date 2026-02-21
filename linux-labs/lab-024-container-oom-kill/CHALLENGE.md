Title: Container Keeps Dying — OOM Kills
Difficulty: ⭐⭐⭐ (Advanced)
Time: 12-15 minutes
Category: Docker / Resources
Skills: docker stats, memory limits, OOM killer, resource constraints

## Scenario

The data processing container keeps getting killed. Docker logs show "OOMKilled" but the team doesn't understand why — the server has plenty of RAM.

> **INCIDENT-5700**: Data processor container OOM killed 12 times today. Server has 16GB RAM free. Container memory limit may be too restrictive for the workload. Need to investigate and set appropriate limits.

Investigate the OOM kills and fix the memory configuration.

## Objectives

1. Get the `data-processor` container running without being OOM killed
2. Set an appropriate memory limit (at least 256MB)
3. The container must stay running with no OOM kills

## What You're Practising

Understanding container resource limits is critical for Kubernetes (where resource requests and limits are fundamental). OOM kills are one of the most common container issues in production.
