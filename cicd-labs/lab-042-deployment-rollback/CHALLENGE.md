Title: Bad Deploy — Rollback Strategy
Difficulty: ⭐⭐⭐ (Advanced)
Time: 20-25 minutes
Category: CI/CD / Deployments
Skills: deployment strategies, rollback, blue-green, canary, health checks

## Scenario

A bad deployment went out and there's no automated rollback. The team needs to implement a deployment strategy with health checks and automatic rollback capability.

> **INCIDENT-CICD-003**: Bad code deployed to production. No rollback mechanism. Manual revert took 45 minutes. Need to implement rollback strategy.

## How to Use This Lab

1. Read the CHALLENGE.md for context
2. Examine the pipeline/workflow files
3. Find and fix the bugs
4. Run validate.sh to check your fixes

**Requires:** Understanding of CI/CD concepts. Some labs can be tested with `act` (local GitHub Actions runner) or Docker.
