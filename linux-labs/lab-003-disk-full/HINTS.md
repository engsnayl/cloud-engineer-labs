# Hints — Lab 003: Disk Full

## Hint 1 — Start with the big picture
Run `df -h` to see how full each filesystem is. Look for the one that's nearly full — that's your target.

## Hint 2 — Drill down by directory
Use `du -sh /data/*` to see which directories under the data partition are using the most space. Then drill deeper with `du -sh /data/logs/*`, `du -sh /data/backups/*`, etc. Follow the trail of big numbers.

## Hint 3 — Find the biggest individual files
`find /data -type f -size +1M -exec ls -lh {} \; 2>/dev/null | sort -k5 -h` will show you every file over 1MB on the data partition, sorted by size. This gives you a hit list of what to investigate.

## Hint 4 — Think before you delete
Not everything big should be deleted. Ask yourself: is this an old log/backup/temp file, or is it live application data? Check the file dates with `ls -la` — old files in `/data/tmp` and `/data/backups` are usually safe. Application data in `/data/myapp/` is not.
