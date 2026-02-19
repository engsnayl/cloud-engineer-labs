Title: Application Can't Write — User and Group Permissions
Difficulty: ⭐⭐ (Intermediate)
Time: 10-15 minutes
Category: User Management / Permissions
Skills: chmod, chown, groups, usermod, ACLs, umask

## Scenario

The application team deployed a new microservice that needs to write to a shared data directory and read configuration files. The application runs as the `appuser` but it can't write to the data directory or read its own config.

> **INCIDENT-5067**: New payment reconciliation service failing on startup. Error: "Permission denied" writing to /opt/data and reading /etc/app/config.yml. Service runs as appuser. Previous services worked fine with root but security policy now requires non-root.

Fix the permissions so the application can operate correctly as a non-root user.

## Objectives

1. Identify permission issues on /opt/data and /etc/app/config.yml
2. Fix directory and file ownership/permissions
3. Ensure appuser is in the correct groups
4. Verify the application can write to the data directory
5. Verify the application can read the config file

## Validation Criteria

- `appuser` can write files to `/opt/data/`
- `appuser` can read `/etc/app/config.yml`
- `/opt/data` is owned by the `appgroup` group
- `appuser` is a member of `appgroup`

## What You're Practising

Running applications as non-root users is a fundamental security practice in cloud environments. Understanding Unix file permissions, group membership, and ownership is essential for deploying secure applications.
