# Hints — Monitoring Lab 051: Memory Leak

## Hint 1 — Watch memory over time
`watch -n 2 'ps aux --sort=-%mem | head 5'` shows which processes are using the most memory. Watch for a few seconds — which one is growing?

## Hint 2 — Check the trend
`cat /var/log/monitoring/memory.log` shows memory usage over time. It should be increasing steadily.

## Hint 3 — Kill the leak, save the app
Identify the PID of the leaking process (the one consuming growing memory), kill it, then write your report to /tmp/incident-report.txt.
