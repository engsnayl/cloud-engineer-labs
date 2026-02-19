# Hints — Lab 006: Cron Not Running

## Hint 1 — Is cron even running?
Check if the cron daemon is running with `pgrep cron` or `service cron status`. If it's not running, start it.

## Hint 2 — Check the crontab syntax
Run `crontab -l` and count the fields. A valid cron entry has exactly 5 time fields followed by the command. Common mistake: adding a 6th field.

## Hint 3 — Permissions matter
Can the script actually execute? Check with `ls -la /opt/scripts/backup.sh`. Use `chmod +x` if needed.
