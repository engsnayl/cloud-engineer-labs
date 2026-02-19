# Hints — Monitoring Lab 050: 500 Errors

## Hint 1 — Check the logs
`docker logs lab050-app-500-errors 2>&1 | grep 500` shows the error pattern. Which endpoint is failing?

## Hint 2 — Look for the pattern
The errors mention a specific cause. `docker logs lab050-app-500-errors 2>&1 | grep ERROR` gives you the details.

## Hint 3 — Write the report
Create `/tmp/incident-report.txt` documenting: which endpoint, what error, root cause (database connection pool exhaustion), and what fix you'd recommend.
