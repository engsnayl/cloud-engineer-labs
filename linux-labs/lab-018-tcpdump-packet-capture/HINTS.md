# Hints — Lab 018: Packet Capture

## Hint 1 — Capture the traffic
`tcpdump -i lo port 9999 -n` captures traffic on port 9999. Watch for a few seconds to see the pattern.

## Hint 2 — Find the source process
`ss -tnp | grep 9999` or `lsof -i :9999` shows which processes are involved.

## Hint 3 — Kill both ends
Kill the client process sending data AND the listener on 9999. Then create your report: `echo "Rogue process PID X was sending data to port 9999 every 3 seconds" > /tmp/incident-report.txt`
