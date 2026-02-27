Title: Broken Automation — Bash Script Debugging
Difficulty: ⭐⭐ (Intermediate)
Time: 15-20 minutes
Category: Scripting / Automation
Skills: Bash scripting, variable expansion, exit codes, error handling, shellcheck

## Scenario

An engineer wrote a Bash script to automate server health checks and log rotation. The script is called by cron every hour but has been silently failing. The monitoring team noticed that health reports haven't been generated in 3 days and old logs aren't being cleaned up.

> **INCIDENT-AUTO-001**: Automated health check and log rotation script failing silently. No health reports generated since Tuesday. Disk usage on log partition growing unchecked.

## Objectives

1. Fix the variable quoting and expansion issues
2. Fix the conditional logic errors
3. Fix the function that handles log rotation
4. Fix error handling so failures are logged, not silently swallowed
5. Fix the exit code handling
6. The script must pass `shellcheck` with no errors
7. The script must run successfully and produce correct output

## How to Use This Lab

1. Start the lab: `docker compose up -d`
2. Exec into the container: `docker exec -it lab038-scripting bash`
3. Review `/opt/scripts/healthcheck.sh`
4. Fix the bugs and run the script
5. Exit and run `./validate.sh` to verify

## Validation

Run `./validate.sh` from the lab directory.
