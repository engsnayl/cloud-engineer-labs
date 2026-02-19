# Hints — Lab 010: Log Rotation Broken

## Hint 1 — Find the big files
Use `du -sh /var/log/app/*` to see which files are oversized. Then look at the logrotate config in `/etc/logrotate.d/app`.

## Hint 2 — Two problems in the config
The config has a wrong path (it looks for logs in the wrong directory) AND a syntax error (missing closing brace). Fix both.

## Hint 3 — Test and force
After fixing the config, test it with `logrotate -d /etc/logrotate.d/app` (dry run). Then force rotation with `logrotate -f /etc/logrotate.d/app`.
