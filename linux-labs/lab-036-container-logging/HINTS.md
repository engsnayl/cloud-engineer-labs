# Hints — Lab 036: Container Logging

## Hint 1 — Where are the logs going?
`docker exec <container> cat /var/log/app.log` — the logs are going to a file, not stdout.

## Hint 2 — Fix the Python logging
Change `logging.basicConfig(filename='/var/log/app.log', ...)` to `logging.basicConfig(stream=sys.stdout, ...)` or remove the filename parameter entirely.

## Hint 3 — Restart the app
After fixing app.py: kill the old process, remove the log file, restart the app. Now `docker logs` should show output.
