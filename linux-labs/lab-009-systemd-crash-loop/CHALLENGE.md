Title: Service Crash Loop — Systemd Unit Failing
Difficulty: ⭐⭐⭐ (Advanced)
Time: 15-20 minutes
Category: Service Management
Skills: systemctl, journalctl, systemd unit files, ExecStart, dependencies

## Scenario

The API gateway service keeps crashing and restarting. Systemd is dutifully restarting it each time, but it immediately fails again. The monitoring system is flooded with alerts.

> **INCIDENT-5134**: api-gateway.service in crash loop. Restarted 47 times in the last hour. Health checks permanently failing. Service was working until the last deployment updated the systemd unit file.

Diagnose the crash loop and get the service running stably.

## Objectives

1. Check the service status and identify the crash loop
2. Read the journal logs to understand why it's failing
3. Examine and fix the systemd unit file
4. Ensure the service starts and stays running
5. Verify the service responds correctly

## Validation Criteria

- api-gateway.service is active (running)
- Service has been running for at least 5 seconds without restarting
- The unit file has correct ExecStart path
- The service responds on its port

## What You're Practising

Systemd is the init system on virtually all modern Linux distributions. Understanding unit files, journal logs, and service dependencies is fundamental to managing any cloud workload that runs on Linux.
