# Hints — Lab 005: Process Eating CPU

## Hint 1 — Find the hog
Use `top` or `ps aux --sort=-%cpu | head` to find which process is eating CPU. The name might not be what you expect.

## Hint 2 — Be surgical
Don't kill everything — the legitimate Python app needs to stay running. Use `kill` with the specific PID, not `killall`.

## Hint 3 — Check the binary
The process name might be disguised. Use `ls -la /usr/local/bin/` to see if anything looks out of place. You can also check with `file /usr/local/bin/analytics-worker`.
