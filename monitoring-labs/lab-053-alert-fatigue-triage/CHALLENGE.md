Title: Too Many Alerts — Alert Fatigue Triage
Difficulty: ⭐⭐ (Intermediate)
Time: 15-20 minutes
Category: Monitoring / Alerting
Skills: alert rules, thresholds, alert grouping, severity levels, runbooks

## Scenario

The on-call engineer is getting 200+ alerts per day. Most are noise. The alerting configuration needs to be triaged — separate real issues from noise, set proper thresholds, and reduce alert fatigue.

> **INCIDENT-MON-004**: On-call burnout. 200+ alerts/day, 95% are non-actionable. Team ignoring alerts. Real incidents being missed in the noise.

## How to Use This Lab

1. Start the lab: `docker compose up -d`
2. Exec in: `docker exec -it lab053-alert-fatigue-triage bash`
3. Investigate and fix the issue
4. Run validate.sh to verify
