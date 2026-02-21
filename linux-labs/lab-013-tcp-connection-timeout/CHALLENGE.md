Title: Service Can't Connect — TCP Connection Debugging
Difficulty: ⭐⭐ (Intermediate)
Time: 10-15 minutes
Category: Networking / TCP
Skills: ss, netstat, telnet, nc, tcpdump, /etc/hosts

## Scenario

The backend API service can't connect to the Redis cache server. Connection attempts are timing out. Both services are on the same network.

> **INCIDENT-5340**: Backend API can't reach Redis. Connection timeout after 30s. Both containers are on the same Docker network. Redis was working 2 hours ago. Network team says nothing changed.

Debug the TCP connectivity issue and restore the connection.

## Objectives

1. Ensure Redis is running and responds to `PING` on port 6379
2. The hostname `redis-server` must resolve to `127.0.0.1`
3. Verify TCP connectivity to `redis-server:6379` succeeds end-to-end

## What You're Practising

TCP connectivity debugging is one of the most fundamental networking skills. In microservices architectures, connection timeouts between services are a daily occurrence. Knowing how to trace the path is essential.
