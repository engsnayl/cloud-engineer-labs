Title: Backup Job Not Running — Cron Misconfigured
Difficulty: ⭐⭐ (Intermediate)
Time: 10-15 minutes
Category: Task Scheduling
Skills: crontab, cron syntax, systemctl, /var/log/syslog, environment variables

## Scenario

The DBA has noticed that the nightly database backup hasn't run for three days. The backup script exists and works when run manually, but the cron job just isn't firing.

> **INCIDENT-4955**: Nightly database backups haven't run since Tuesday. Backup script `/opt/scripts/backup.sh` works when executed manually. Cron job appears to be configured but not executing.

You need to diagnose why the cron job isn't running and fix it.

## Objectives

1. Check if the cron daemon is running
2. Find and fix issues with the crontab configuration
3. Ensure the backup script has correct permissions
4. Verify the cron job runs successfully
5. Check that the backup output file is created

## Validation Criteria

- Cron daemon is running
- `crontab -l` shows a valid backup job
- `/opt/scripts/backup.sh` is executable
- Backup script runs successfully when triggered
- `/var/backups/db-backup.sql` exists

## What You're Practising

Cron is the backbone of scheduled automation in Linux. Misconfigured cron jobs are a silent killer — they fail without anyone noticing until something critical hasn't happened. Understanding cron syntax, environment, and logging is essential.
