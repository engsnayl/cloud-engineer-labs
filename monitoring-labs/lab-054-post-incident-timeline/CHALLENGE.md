Title: What Happened? — Post-Incident Timeline Reconstruction
Difficulty: ⭐⭐⭐ (Advanced)
Time: 25-35 minutes
Category: Monitoring / Incident Response
Skills: log correlation, timeline construction, root cause analysis, incident reports

## Scenario

You walk in this morning and find this ticket waiting for you.

> **INCIDENT-MON-005** — Priority: SEV-1 (resolved)
>
> Major outage overnight. Payment processing was unavailable for an extended period. Customers were getting 503 errors. The on-call engineer resolved it in the early hours but didn't write anything up.
>
> CTO wants a full post-incident report by EOD. Use whatever you can find on the box.
>
> — _Eng Manager, 08:42_

That's all you've got. No log paths, no service list, no idea what failed first. Welcome to incident response.

## Objectives

1. Write a post-incident report to `/tmp/post-incident-report.txt`
2. Identify the root cause (not just the symptom)
3. Include a chronological timeline with timestamps
4. Document the impact on services and users
5. Include resolution steps and action items to prevent recurrence

## How to Use This Lab

1. Start the lab: `docker compose up -d`
2. Exec in: `docker exec -it lab054-post-incident-timeline bash`
3. Investigate. Find the logs. Reconstruct what happened.
4. Run validate.sh to verify your report
