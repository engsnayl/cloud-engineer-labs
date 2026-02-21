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

1. Get `/data` mounted as a filesystem (must be on a separate device from `/`)
2. Ensure the data files are accessible (e.g. `/data/db-data.conf` must exist)
3. Fix the `/etc/fstab` entry so the mount persists across reboots

## What You're Practising

Volume mounting issues are common after reboots, especially in cloud environments where EBS volumes or persistent disks need to be correctly configured in fstab. Getting this wrong means data loss or service outages.
