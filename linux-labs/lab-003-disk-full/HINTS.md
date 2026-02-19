# Hints — Lab 003: Disk Full

## Hint 1 — Finding what's eating space
`du -sh /*` gives you a top-level view. Then drill into the biggest directories with `du -sh /var/*`, `du -sh /var/log/*`, etc. The `find` command with `-size` flag is your friend: `find / -type f -size +10M`.

## Hint 2 — Deleting files might not free space
If a process has a file open and you delete it, the space isn't actually freed until the process releases the file descriptor. Check for this with `lsof +L1` or look in `/proc/*/fd` for deleted entries. You'll need to deal with the process first.

## Hint 3 — Preventing recurrence
Look into `/etc/logrotate.d/` — you need to create a config file for the application logs. A basic logrotate config rotates logs when they hit a certain size and keeps only a few old copies.
