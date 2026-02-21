Title: What Happened? — Post-Incident Timeline Reconstruction
Difficulty: ⭐⭐⭐ (Advanced)
Time: 20-25 minutes
Category: Monitoring / Incident Response
Skills: log correlation, timeline construction, root cause analysis, incident reports

## Scenario

A major incident occurred overnight and you need to reconstruct what happened from the available logs and metrics. Build a timeline and write the post-incident report.

> **INCIDENT-MON-005**: Major outage from 02:00-04:30. Payment processing down for 2.5 hours. Multiple systems affected. CTO wants a full post-incident report by EOD.

## Objectives

1. Write a post-incident report to `/tmp/post-incident-report.txt`
2. Identify the root cause (investigate disk space, WAL files, and database logs)
3. Include a timeline with timestamps from the incident
4. Include action items to prevent recurrence
5. Document the impact on services

## How to Use This Lab

1. Start the lab: `docker compose up -d`
2. Exec in: `docker exec -it lab054-post-incident-timeline bash`
3. Investigate and fix the issue
4. Run validate.sh to verify
