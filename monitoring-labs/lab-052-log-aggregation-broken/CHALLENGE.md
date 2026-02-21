Title: Logs Missing — Log Aggregation Pipeline Broken
Difficulty: ⭐⭐ (Intermediate)
Time: 12-15 minutes
Category: Monitoring / Logging
Skills: syslog, rsyslog, log forwarding, log formats, log parsing

## Scenario

The centralised logging system isn't receiving logs from this server. Rsyslog is configured to forward logs but they're not arriving at the aggregation service.

> **INCIDENT-MON-003**: No logs from app-server-03 in central logging for 48 hours. Rsyslog is installed but forwarding appears broken. Need to fix the log pipeline.

## Objectives

1. Ensure rsyslog is running
2. Fix the forwarding configuration to point to the correct port (5514)
3. Verify logs are being forwarded — test messages must arrive at the aggregation endpoint

## How to Use This Lab

1. Start the lab: `docker compose up -d`
2. Exec in: `docker exec -it lab052-log-aggregation-broken bash`
3. Investigate and fix the issue
4. Run validate.sh to verify
