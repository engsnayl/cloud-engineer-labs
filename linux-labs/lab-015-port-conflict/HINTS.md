# Hints — Lab 015: Port Conflict

## Hint 1 — Find what's using the port
`ss -tlnp | grep 8080` or `lsof -i :8080` shows which process is bound to port 8080.

## Hint 2 — Kill the stale process
Note the PID from the previous command and use `kill <PID>` to stop it.

## Hint 3 — Start the real service
`python3 /opt/api.py &` starts the actual API service. Verify with `curl localhost:8080`.
