Title: DNS Resolution Failing — Application Can't Reach External Services
Difficulty: ⭐⭐ (Intermediate)
Time: 15-20 minutes
Category: Networking / DNS
Skills: /etc/resolv.conf, /etc/hosts, dig, nslookup, DNS troubleshooting

## Scenario

A developer has raised an urgent ticket:

> **INCIDENT-4803**: Our payment processing application on the app server can't reach the payment gateway API. All outbound HTTP requests are failing with "Could not resolve host". This started after last night's maintenance window where the network team made DNS changes.

You need to find out why DNS isn't working and fix it. The application also depends on an internal service called `payments-api.internal` which must resolve to `10.0.1.50`.

## Objectives

1. Confirm that DNS resolution is broken (try resolving a known domain)
2. Investigate `/etc/resolv.conf` and test whether the configured nameservers actually work
3. Fix the nameserver configuration so external DNS resolution works
4. Investigate `/etc/hosts` and ensure `payments-api.internal` resolves to `10.0.1.50`
5. Verify both external DNS and the internal hostname work correctly

## What You're Practising

DNS issues are the single most common cause of "it's not working" in cloud environments. The skill here is systematic testing — not just looking at config files, but actually *testing* each nameserver to prove whether it works or not. In production you'll use this exact approach: confirm the symptom, check the config, test each component, fix, verify.
