# Hints — Monitoring Lab 054: Post-Incident Timeline

## Hint 1 — Start with the logs
Read all four log files chronologically. Start with /var/log/infra/system.log to understand the infrastructure failure, then trace through the application impact.

## Hint 2 — Build the timeline
Key events: disk warning (01:55), disk critical (02:00), postgres down (02:00:15), payment-api failing (02:00:18), alert sent (02:10), engineer responds (02:25), resolution starts (02:30), service restored (02:50).

## Hint 3 — Structure your report
Include: Summary (1 paragraph), Timeline (chronological events), Root Cause (disk full due to WAL accumulation), Impact (payment processing down ~50 min, X failed requests), Resolution (cleared WAL, restarted DB), Action Items (automated WAL cleanup, better disk alerts).
