Title: Mystery Traffic — Packet Capture Analysis
Difficulty: ⭐⭐⭐ (Advanced)
Time: 15-20 minutes
Category: Networking / Debugging
Skills: tcpdump, packet analysis, network interfaces, TCP flags, filtering

## Scenario

Something is making unexpected outbound connections from the server. Security has flagged unusual traffic patterns and you need to identify what's happening using packet capture.

> **INCIDENT-5499**: IDS flagging unusual outbound connections to unknown IP on port 9999. Need to identify the source process and stop the traffic. Use packet capture to investigate.

## Objectives

1. Use tcpdump to identify the suspicious traffic pattern
2. Stop the rogue exfiltration process
3. Ensure nothing is listening on port 9999
4. The legitimate web service on port 8080 must still be running
5. Document your findings in `/tmp/incident-report.txt`

## What You're Practising

Packet capture is a critical debugging and security investigation tool. Being able to use tcpdump to identify traffic patterns is a key skill for cloud engineers and SREs.
