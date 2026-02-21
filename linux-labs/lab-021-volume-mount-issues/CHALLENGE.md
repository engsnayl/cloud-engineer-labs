Title: Data Missing — Docker Volume Mount Problems
Difficulty: ⭐⭐ (Intermediate)
Time: 10-15 minutes
Category: Docker / Storage
Skills: docker volumes, bind mounts, permissions, volume inspection

## Scenario

The database container was restarted and all data disappeared. The team thought they had persistent storage configured but the data didn't survive the restart.

> **INCIDENT-5590**: Database container restarted and all customer data is gone. Team claims volumes were configured. Need to investigate the volume setup, recover any data, and ensure persistence.

Fix the volume configuration so data persists across container restarts.

## Objectives

1. Investigate why data didn't persist
2. Check for any existing Docker volumes with data
3. Create proper volume mount configuration
4. Restore data from the orphaned volume
5. Verify data survives a container restart

## What You're Practising

Understanding Docker storage — the difference between named volumes, bind mounts, and anonymous volumes — is essential. Data loss from missing volume mounts is one of the most painful mistakes in container operations.
