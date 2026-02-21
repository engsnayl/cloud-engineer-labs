Title: Server Slow — Runaway Process Consuming CPU
Difficulty: ⭐⭐ (Intermediate)
Time: 8-12 minutes
Category: Process Management
Skills: top, htop, ps, kill, nice, renice, strace

## Scenario

The monitoring dashboard is showing 100% CPU utilisation on the application server. Response times have gone through the roof and customers are complaining.

> **INCIDENT-4901**: App server CPU pegged at 100%. Customer-facing API response times >10s. Autoscaling hasn't kicked in because it's a single poorly-behaved process, not genuine load.

You need to identify the rogue process, deal with it, and ensure the legitimate application is running correctly.

## Objectives

1. Identify which process is consuming all the CPU
2. Determine if it's a legitimate process gone wrong or something unexpected
3. Kill the rogue process
4. Ensure the legitimate application process (python3 app.py) is still running
5. Verify CPU usage has returned to normal

## What You're Practising

Identifying and killing runaway processes is a daily task for cloud engineers. You need to know how to quickly find what's eating resources, decide whether to kill it, and do so without taking down legitimate services.
