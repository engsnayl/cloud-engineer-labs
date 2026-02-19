Title: Where Are The Logs — Container Logging Debugging
Difficulty: ⭐⭐ (Intermediate)
Time: 10-15 minutes
Category: Docker / Logging
Skills: docker logs, log drivers, stdout/stderr, log rotation, logging best practices

## Scenario

The application container's logs are empty despite the app clearly running and processing requests. Logs are being written to a file inside the container instead of stdout/stderr.

> **INCIDENT-5735**: `docker logs app-container` returns nothing. Application is running and serving traffic but we can't see any logs. Monitoring can't scrape container logs. Need to fix logging.

## Objectives

1. Check why docker logs shows nothing
2. Find where the application is actually logging
3. Fix the application to log to stdout/stderr
4. Verify docker logs shows output
5. Ensure log rotation is sensible

## Validation Criteria

- `docker logs` shows application output
- Application is still running and responding
- No large log files inside the container
- Container is running with appropriate log options

## What You're Practising

Container logging best practice is stdout/stderr, which Docker captures and forwards to logging drivers. Applications that log to files inside containers break the container logging pipeline.
