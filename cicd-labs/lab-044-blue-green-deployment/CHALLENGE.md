Title: Zero-Downtime Deploy — Blue/Green Switch
Difficulty: ⭐⭐⭐ (Advanced)
Time: 20-25 minutes
Category: CI/CD / Blue-Green
Skills: blue-green deployment, nginx upstream switching, zero downtime, traffic routing

## Scenario

The team needs to implement blue/green deployments to achieve zero-downtime releases. Currently deploys cause a brief outage as the container restarts.

> **INCIDENT-CICD-004**: Every deployment causes 10-30 seconds of downtime. SLA requires 99.99% uptime. Need zero-downtime deployment strategy.

## Objectives

1. Create an executable `switch.sh` script for blue/green environment switching
2. The switch script must include health checking before completing the switch
3. The script must reload Nginx to route traffic to the new environment
4. The script must reference blue and green environments

## How to Use This Lab

1. Read the CHALLENGE.md for context
2. Examine the pipeline/workflow files
3. Find and fix the bugs
4. Run validate.sh to check your fixes

**Requires:** Understanding of CI/CD concepts. Some labs can be tested with `act` (local GitHub Actions runner) or Docker.
