# Hints — Lab 021: Volume Mount Issues

## Hint 1 — Find the orphaned volume
`docker volume ls` shows all volumes. `docker volume inspect db-data` shows details. The data is there, just not mounted.

## Hint 2 — Recreate with the volume
Stop the current container: `docker rm -f database`. Then start it with the volume: `docker run -d --name database -v db-data:/data python:3.11-slim python3 -c "import time; import os; os.makedirs('/data', exist_ok=True); [time.sleep(60) for _ in iter(int, 1)]"`

## Hint 3 — Verify persistence
Check the data is there, then restart: `docker restart database` and check again.
