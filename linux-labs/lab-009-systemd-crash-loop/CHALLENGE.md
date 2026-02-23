Title: Service Crash Loop — Systemd Unit Failing
Difficulty: ⭐⭐⭐ (Advanced)
Time: 15-20 minutes
Category: Service Management
Skills: systemctl, journalctl, systemd unit files, ExecStart, dependencies

## Scenario

⚠️⚠️⚠️⚠️⚠️ 
Raspberry Pi Users: Docker Compose doesn't support `cgroupns` on Pi. Start this lab manually:

docker rm -f lab009-systemd-crash-loop 2>/dev/null
docker build -t lab009 linux-labs/lab-009-systemd-crash-loop/
docker run -d --name lab009-systemd-crash-loop --privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw lab009 /sbin/init
docker exec -it lab009-systemd-crash-loop bash
⚠️⚠️⚠️⚠️⚠️

The API gateway service keeps crashing and restarting. Systemd is dutifully restarting it each time, but it immediately fails again. The monitoring system is flooded with alerts.

> **INCIDENT-5134**: api-gateway.service in crash loop. Restarted 47 times in the last hour. Health checks permanently failing. Service was working until the last deployment updated the systemd unit file.

Diagnose the crash loop and get the service running stably.

## Objectives

1. Get `api-gateway.service` running and stable (must stay up for more than 5 seconds without restarting)
2. Fix the systemd unit file — the `ExecStart` must reference the correct application filename
3. The service must respond on port 3000

## What You're Practising

Systemd is the init system on virtually all modern Linux distributions. Understanding unit files, journal logs, and service dependencies is fundamental to managing any cloud workload that runs on Linux.
