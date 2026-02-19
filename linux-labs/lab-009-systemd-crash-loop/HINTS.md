# Hints — Lab 009: Systemd Crash Loop

## Hint 1 — Check the logs
`systemctl status api-gateway.service` shows recent status. `journalctl -u api-gateway.service -n 20` shows the last 20 log lines. The error messages tell you exactly what's wrong.

## Hint 2 — Look at the unit file carefully
`cat /etc/systemd/system/api-gateway.service` — compare the ExecStart path with what actually exists in /opt/. Check for typos. Also check if the WorkingDirectory exists and if the User exists.

## Hint 3 — After fixing, reload and restart
After editing the unit file: `systemctl daemon-reload` then `systemctl restart api-gateway.service`. You need daemon-reload every time you change a unit file.
