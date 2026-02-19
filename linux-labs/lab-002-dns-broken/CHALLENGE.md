Title: DNS Resolution Failing — Application Can't Reach External Services
Difficulty: ⭐⭐ (Intermediate)
Time: 10-15 minutes
Category: Networking / DNS
Skills: resolv.conf, dig/nslookup, systemd-resolved, /etc/hosts, network debugging

## Scenario

A developer has raised an urgent ticket:

> **INCIDENT-4803**: Our payment processing application on the app server can't reach the payment gateway API. All outbound HTTP requests are failing with "Could not resolve host". This started after last night's maintenance window where the network team made DNS changes.

You need to restore DNS resolution on this server so the application can reach external services again.

## Objectives

1. Diagnose why DNS resolution is failing
2. Identify all DNS-related misconfigurations
3. Restore working DNS resolution
4. Ensure the internal service `payments-api.internal` resolves to `10.0.1.50`
5. Confirm external DNS resolution works (e.g. `google.com`)

## Validation Criteria

- `dig google.com` returns a valid A record
- `curl -s ifconfig.me` returns successfully (proves external connectivity + DNS)
- `getent hosts payments-api.internal` resolves to `10.0.1.50`
- `/etc/resolv.conf` contains at least one valid nameserver

## What You're Practising

DNS issues are the single most common cause of "it's not working" in cloud environments. VPC DNS settings, resolv.conf corruption, and missing hosts entries account for a huge proportion of real incidents.
