Title: Web Server Down — Nginx Won't Start
Difficulty: ⭐⭐ (Intermediate)
Time: 10-15 minutes
Category: Service Troubleshooting
Skills: systemctl, nginx config, logs, file permissions

## Scenario

You've just started your shift as a Cloud Engineer at a fintech company. The on-call engineer has escalated a P1 incident to you:

> **INCIDENT-4721**: Customer portal is returning 502 Bad Gateway. The Nginx reverse proxy on the web server has stopped responding. Previous engineer attempted a fix but made things worse. Server needs to be back online ASAP.

You SSH into the server and need to get Nginx running again.

## Objectives

1. Diagnose why Nginx is not running
2. Fix ALL configuration issues — `nginx -t` must pass cleanly
3. Get Nginx running and serving — `curl localhost` must return HTTP 200
4. Ensure the Nginx log directory (`/var/log/nginx`) is writable
5. Ensure Nginx is enabled in systemd (survives reboot)

## What You're Practising

This simulates a real incident response scenario. In production, web servers fail for multiple overlapping reasons — a config typo here, a permission issue there. The skill is systematic diagnosis rather than guessing.
