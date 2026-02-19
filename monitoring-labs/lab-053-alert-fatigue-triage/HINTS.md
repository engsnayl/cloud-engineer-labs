# Hints — Monitoring Lab 053: Alert Fatigue

## Hint 1 — Review each alert critically
Ask: "Would I wake someone up for this?" If no, it's not critical. CPU at 3%? Not an issue. Response time of 42ms? Normal.

## Hint 2 — Proper thresholds
CPU: warn at 70%, critical at 90%. Memory: warn at 80%, critical at 90%. Disk: warn at 80%, critical at 90%. 5xx: rate > 5%, not individual errors. SSL: warn at 30 days, critical at 7 days.

## Hint 3 — Use severity levels
critical = page on-call immediately. warning = review in business hours. info = dashboard only. Most of these alerts should be warning or info, not critical.
