Title: Zero-Downtime Deploy — Blue/Green Switch
Difficulty: ⭐⭐⭐ (Advanced)
Time: 20-25 minutes
Category: CI/CD / Blue-Green
Skills: blue-green deployment, nginx upstream switching, zero downtime, traffic routing

## Scenario

The team needs to implement blue/green deployments to achieve zero-downtime releases. Currently deploys cause a brief outage as the container restarts.

> **INCIDENT-CICD-004**: Every deployment causes 10-30 seconds of downtime. SLA requires 99.99% uptime. Need zero-downtime deployment strategy.

## How to Use This Lab

1. Read the CHALLENGE.md for context
2. Examine the pipeline/workflow files
3. Find and fix the bugs
4. Run validate.sh to check your fixes

**Requires:** Understanding of CI/CD concepts. Some labs can be tested with `act` (local GitHub Actions runner) or Docker.
