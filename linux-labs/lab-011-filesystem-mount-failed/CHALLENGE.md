Title: Data Volume Missing — Filesystem Mount Failed
Difficulty: ⭐⭐⭐ (Advanced)
Time: 15-20 minutes
Category: Storage / Filesystems
Skills: mount, fstab, lsblk, blkid, df, filesystem creation

## Scenario

The database server rebooted after a kernel update and the data volume didn't mount automatically. The database can't start because its data directory is empty — it's pointing at the mount point which has no filesystem mounted.

> **INCIDENT-5245**: Database server data volume /data not mounted after reboot. PostgreSQL refusing to start — data directory appears empty. fstab entry exists but mount is failing. Data is NOT lost — the volume is there, just not mounted.

Mount the data volume and verify the data is accessible.

## Objectives

1. Identify why the volume isn't mounted
2. Check and fix the fstab entry
3. Successfully mount the volume
4. Verify the data files are accessible
5. Ensure the mount persists across reboots (correct fstab)

## Validation Criteria

- /data is mounted
- Files exist in /data (at least db-data.conf)
- /etc/fstab has a valid entry for /data
- `df /data` shows it's on a separate filesystem

## What You're Practising

Volume mounting issues are common after reboots, especially in cloud environments where EBS volumes or persistent disks need to be correctly configured in fstab. Getting this wrong means data loss or service outages.
