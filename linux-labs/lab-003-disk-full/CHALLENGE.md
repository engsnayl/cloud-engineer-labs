Title: Disk Full — Application Failing to Write
Difficulty: ⭐⭐ (Intermediate)
Time: 15-20 minutes
Category: Storage / Disk Management
Skills: df, du, find, lsof, log management, disk cleanup

## Scenario

You've been paged at 7am with an urgent alert:

> **INCIDENT-4855**: The reporting application on `reports-server` is failing with "No space left on device" errors. Users cannot generate or download reports. The application stores everything on a dedicated data partition mounted at `/data` and needs at least 50MB of free space to function. The 180MB partition was plenty when it was provisioned, but something has consumed nearly all of it.

Your job is to find what's eating the disk space and free up enough room for the application to work again. Be careful — don't just delete everything. Some files are important.

## Objectives

1. Confirm the disk is full using `df`
2. Identify which directories are consuming the most space using `du`
3. Find and remove files that are safe to delete (old logs, stale backups, temp files)
4. Ensure at least 50MB of free space is available on `/data`
5. Ensure the application directory `/data/myapp/` still exists and is writable

## What You're Practising

Disk space issues are one of the most common reasons applications fail in production. The skill is methodical investigation — starting with `df` to confirm the problem, then using `du` to drill down directory by directory, and `find` to locate the biggest offenders. Knowing what's safe to delete versus what's critical is a judgement call you'll make constantly as a Cloud Engineer.
