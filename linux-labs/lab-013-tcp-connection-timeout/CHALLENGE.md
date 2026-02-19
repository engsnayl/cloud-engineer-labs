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

1. Verify Redis is running and listening on the expected port
2. Check if the API can resolve the Redis hostname
3. Identify the network connectivity issue
4. Fix the connection path between services
5. Confirm the API can connect to Redis

## Validation Criteria

- Redis process is running and listening on port 6379
- `nc -zv redis-server 6379` connects successfully from the app container
- /etc/hosts correctly resolves redis-server
- Application can reach Redis

## What You're Practising

TCP connectivity debugging is one of the most fundamental networking skills. In microservices architectures, connection timeouts between services are a daily occurrence. Knowing how to trace the path is essential.
