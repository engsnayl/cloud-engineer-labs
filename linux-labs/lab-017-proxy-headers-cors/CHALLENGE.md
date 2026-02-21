Title: API Requests Failing — Proxy Headers and CORS Issues
Difficulty: ⭐⭐⭐ (Advanced)
Time: 15-20 minutes
Category: Networking / HTTP
Skills: nginx proxy_set_header, CORS, X-Forwarded-For, Host header, OPTIONS method

## Scenario

The frontend application can't make API calls through the reverse proxy. Browser shows CORS errors and the backend is receiving wrong headers.

> **INCIDENT-5478**: Frontend app getting CORS errors on all API calls. Backend logging shows requests arriving with wrong Host header. Pre-flight OPTIONS requests returning 405.

## Objectives

1. Fix the Nginx proxy configuration — `nginx -t` must pass
2. Responses must include the `Access-Control-Allow-Origin` CORS header
3. OPTIONS pre-flight requests must return HTTP 200 or 204
4. The correct `Host` header must be forwarded to the backend

## What You're Practising

Understanding HTTP headers, CORS, and reverse proxy configuration is essential for any web-facing infrastructure. These issues are incredibly common when setting up API gateways.
