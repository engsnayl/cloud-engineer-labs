Title: Disk Full — Application Logging Has Consumed All Storage
Difficulty: ⭐ (Beginner-Intermediate)
Time: 10-15 minutes
Category: Storage / Disk Management
Skills: df, du, find, log rotation, file management, process investigation

## Scenario

The monitoring system has fired a critical alert:

> **ALERT-CRIT-DISK**: Disk usage on app-server-03 has exceeded 95%. Application health checks are failing because the app can't write to its log files. Database writes are also failing.

The application team says they didn't change anything — this just gradually got worse. You need to free up disk space, identify what's consuming it, and put a fix in place so it doesn't happen again.

## Objectives

1. Identify what is consuming the most disk space
2. Free up disk space to get below 70% usage
3. Find and deal with the runaway log files
4. Identify if any deleted files are still being held open by processes
5. Create a basic log rotation config to prevent this recurring

## Validation Criteria

- Disk usage is below 70%
- No single log file is larger than 10MB
- A logrotate configuration exists for the application logs
- The application log directory exists and is writable

## What You're Practising

Disk full is one of the most common production incidents. The twist is that it's not always obvious — sometimes deleted files are still held by processes, sometimes logs are in unexpected places, sometimes temp files accumulate. Systematic investigation with du and find is the skill here.
