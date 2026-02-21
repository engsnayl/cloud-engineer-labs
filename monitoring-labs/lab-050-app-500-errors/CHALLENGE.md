Title: Application Throwing 500s — Root Cause Analysis
Difficulty: ⭐⭐ (Intermediate)
Time: 15-20 minutes
Category: Monitoring / RCA
Skills: log analysis, error codes, stack traces, application debugging, grep, awk

## Scenario

The application is returning HTTP 500 errors intermittently. You need to dig through logs, identify the pattern, and find the root cause.

> **INCIDENT-MON-001**: 500 error rate spiked to 15%. Not all requests failing — seems intermittent. Application logs are verbose. Find the pattern and root cause.

## Objectives

1. Investigate the application logs to identify the root cause of the 500 errors
2. Identify the affected endpoint and the underlying issue (e.g. database connection problems)
3. Ensure the application is still running (`/api/health` returns OK)
4. Write an incident report to `/tmp/incident-report.txt` documenting the root cause and affected endpoint

## How to Use This Lab

1. Start the lab: `docker compose up -d`
2. Exec in: `docker exec -it lab050-app-500-errors bash`
3. Investigate and fix the issue
4. Run validate.sh to verify
