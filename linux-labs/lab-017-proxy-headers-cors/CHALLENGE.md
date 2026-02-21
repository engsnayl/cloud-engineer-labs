Title: API Requests Failing — Proxy Headers and CORS Issues
Difficulty: ⭐⭐⭐ (Advanced)
Time: 15-20 minutes
Category: Networking / HTTP
Skills: nginx proxy_set_header, CORS, X-Forwarded-For, Host header, OPTIONS method

## Scenario

The frontend application can't make API calls through the reverse proxy. Browser shows CORS errors and the backend is receiving wrong headers.

> **INCIDENT-5478**: Frontend app getting CORS errors on all API calls. Backend logging shows requests arriving with wrong Host header. Pre-flight OPTIONS requests returning 405.

## Objectives

1. Check the Nginx proxy configuration for missing headers
2. Add proper CORS headers to the response
3. Handle OPTIONS pre-flight requests
4. Pass correct upstream headers (Host, X-Forwarded-For, X-Real-IP)
5. Verify API calls work through the proxy

## What You're Practising

Understanding HTTP headers, CORS, and reverse proxy configuration is essential for any web-facing infrastructure. These issues are incredibly common when setting up API gateways.
