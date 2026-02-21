Title: Load Balancer Not Distributing — Reverse Proxy Misconfigured
Difficulty: ⭐⭐⭐ (Advanced)
Time: 15-20 minutes
Category: Networking / Load Balancing
Skills: nginx reverse proxy, upstream config, health checks, load balancing algorithms

## Scenario

The Nginx load balancer in front of the application tier isn't distributing traffic correctly. One backend gets all requests while the others sit idle.

> **INCIDENT-5450**: Uneven load distribution. Backend server 1 at 100% CPU, servers 2 and 3 at 0%. Nginx LB should be round-robin but all traffic hitting one backend.

## Objectives

1. Check the Nginx upstream configuration
2. Identify why traffic isn't being distributed
3. Fix the upstream block to correctly load balance
4. Verify all three backends receive traffic
5. Ensure health checks are configured

## What You're Practising

Load balancing configuration is central to high availability. Whether it's Nginx, HAProxy, or an ALB, understanding upstream health checks and distribution algorithms is essential.
