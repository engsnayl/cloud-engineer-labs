# Hints — Lab 003: Disk Full

## Hint 1 — Start with the big picture
Run `df -h` to see how full the disk is. This confirms the problem and shows you which filesystem is affected.

## Hint 2 — Drill down by directory
Use `du -sh /*` to see which top-level directories are using the most space. Then drill deeper into the biggest ones with `du -sh /var/*`, `du -sh /var/log/*`, etc. Follow the trail of big numbers.

## Hint 3 — Find the biggest individual files
`find / -type f -size +1M -exec ls -lh {} \; 2>/dev/null | sort -k5 -h` will show you every file over 1MB, sorted by size. This gives you a hit list of what to investigate.

## Hint 4 — Think before you delete
Not everything big should be deleted. Ask yourself: is this an old log/backup/temp file, or is it live application data? Check the file dates with `ls -la` — old files in `/tmp` and `/opt/backups` are usually safe. Application data in `/var/lib/myapp/` is not.
