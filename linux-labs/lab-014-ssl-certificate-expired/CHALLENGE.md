Title: HTTPS Broken — SSL Certificate Issues
Difficulty: ⭐⭐⭐ (Advanced)
Time: 15-20 minutes
Category: Networking / TLS
Skills: openssl, certificate inspection, nginx SSL config, self-signed certs

## Scenario

The internal dashboard is showing SSL errors. The certificate has expired and the Nginx SSL configuration has additional issues preventing HTTPS from working.

> **INCIDENT-5389**: Internal dashboard returning SSL errors. Certificate appears to have expired. Service must be available over HTTPS on port 443. Generate a new self-signed certificate and fix the Nginx SSL config.

Restore HTTPS access to the dashboard.

## Objectives

1. Generate a new self-signed SSL certificate (the current one is expired)
2. Configure Nginx to use the new certificate — `nginx -t` must pass
3. Get Nginx running and serving HTTPS on port 443
4. The SSL certificate must not be expired

## What You're Practising

SSL/TLS certificate management is a critical cloud engineering skill. Certificate expiry is one of the most common causes of outages — even major companies have been brought down by expired certs.
