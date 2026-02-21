Title: Application Unreachable — Firewall Rules Blocking Traffic
Difficulty: ⭐⭐⭐ (Advanced)
Time: 15-20 minutes
Category: Networking / Security
Skills: iptables, netstat/ss, firewall rules, network debugging, tcpdump

## Scenario

After a security audit, the security team applied new firewall rules to the application server. Now the web application on port 8080 and the health check endpoint on port 8081 are both unreachable, even though the processes are running and listening.

> **INCIDENT-5012**: Web app and health checks unreachable after firewall changes. Both processes confirmed running. Security team's iptables changes appear to have blocked legitimate traffic. Kubernetes health checks failing — pod will be killed in 10 minutes if not resolved.

You need to fix the firewall rules to allow legitimate traffic while keeping the security posture intact.

## Objectives

1. Get the application responding on port 8080 (HTTP 200)
2. Get the health check responding on port 8081 (HTTP 200)
3. Maintain the default DROP policy on the INPUT chain (don't just flush everything)
4. Ensure loopback (localhost) traffic is allowed

## What You're Practising

Firewall misconfigurations are one of the most common causes of 'it worked before the change' incidents. Understanding iptables rules, chain ordering, and how to debug connectivity with the firewall in place is critical for any cloud engineer.
