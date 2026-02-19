# Hints — Monitoring Lab 052: Log Aggregation

## Hint 1 — Check rsyslog
Is rsyslog running? `pgrep rsyslog` or `service rsyslog status`. If not, start it.

## Hint 2 — Check the forwarding config
`cat /etc/rsyslog.d/50-forwarding.conf` — what port is it forwarding to? The aggregator is listening on 5514.

## Hint 3 — Test the pipeline
After fixing, run `/opt/generate-logs.sh &` to create logs, then check if they appear in `/var/log/aggregated.log`.
