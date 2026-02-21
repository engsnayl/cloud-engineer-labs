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

1. Get the database container running
2. Restore the customer data — `/data/customers.db` must exist and contain customer records
3. Mount the `db-data` Docker volume to ensure data persists
4. Verify data survives a container restart

## What You're Practising

Understanding Docker storage — the difference between named volumes, bind mounts, and anonymous volumes — is essential. Data loss from missing volume mounts is one of the most painful mistakes in container operations.
