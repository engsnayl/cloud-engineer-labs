Title: Disk Filling Up — Log Rotation Not Working
Difficulty: ⭐⭐ (Intermediate)
Time: 10-15 minutes
Category: Log Management
Skills: logrotate, du, find, cron, syslog configuration

## Scenario

The disk usage alert has fired again — the same server, the same problem. Application logs are growing without limit because log rotation is broken.

> **INCIDENT-5198**: /var/log partition at 90%. Application log files are 500MB+. Logrotate is configured but not rotating. This is the third time this month — we need a permanent fix.

Fix the log rotation configuration and clean up the oversized logs.

## Objectives

1. Clean up oversized log files — no active log file should be larger than 10MB
2. Fix the logrotate configuration so it passes validation (`logrotate -d`)
3. Ensure the logrotate config targets the correct log directory (`/var/log/app/`)
4. Run logrotate and verify it creates rotated log files

## What You're Practising

Unmanaged log files are the #1 cause of disk-full incidents in production. Setting up proper log rotation is one of those unsexy but critical tasks every cloud engineer needs to master.
