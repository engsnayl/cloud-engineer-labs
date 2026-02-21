Title: Memory Growing — Detect and Diagnose a Memory Leak
Difficulty: ⭐⭐⭐ (Advanced)
Time: 15-20 minutes
Category: Monitoring / Performance
Skills: free, ps, /proc/meminfo, memory profiling, process monitoring, trends

## Scenario

The application server's memory usage is growing steadily. It starts fine but over time consumes more and more RAM until the OOM killer strikes.

> **INCIDENT-MON-002**: Memory usage trending up linearly. Server starts at 30% memory, now at 75% after 6 hours. OOM kill expected within 2 hours. Find the leaking process.

## Objectives

1. Identify and kill the process that is leaking memory
2. Ensure the legitimate application process is still running (do not kill the wrong one)
3. Write an incident report to `/tmp/incident-report.txt` describing the memory leak

## How to Use This Lab

1. Start the lab: `docker compose up -d`
2. Exec in: `docker exec -it lab051-memory-leak-detection bash`
3. Investigate and fix the issue
4. Run validate.sh to verify
