Title: Where Are The Logs — Container Logging Debugging
Difficulty: ⭐⭐ (Intermediate)
Time: 10-15 minutes
Category: Docker / Logging
Skills: docker logs, log drivers, stdout/stderr, log rotation, logging best practices

## Scenario

The application container's logs are empty despite the app clearly running and processing requests. Logs are being written to a file inside the container instead of stdout/stderr.

> **INCIDENT-5735**: `docker logs app-container` returns nothing. Application is running and serving traffic but we can't see any logs. Monitoring can't scrape container logs. Need to fix logging.

## Objectives

1. Fix the application so it logs to stdout/stderr (visible via `docker logs`)
2. The application must still respond on port 8080
3. No oversized log files (over 1MB) should accumulate inside the container

## What You're Practising

Container logging best practice is stdout/stderr, which Docker captures and forwards to logging drivers. Applications that log to files inside containers break the container logging pipeline.
