# Solution Walkthrough — Packet Capture (tcpdump)

## The Problem

There is suspicious network activity on the server. A rogue process is quietly sending data labeled "EXFIL DATA PACKET" to port 9999 every 3 seconds, where a listener process is receiving it. This simulates a data exfiltration scenario — a compromised process secretly sending sensitive data out of the system.

The setup has **three processes**:
1. **A legitimate web server on port 8080** — this is the real application and must stay running.
2. **A rogue "exfiltration" client** — a Python script that connects to port 9999 every 3 seconds and sends data. This is the attacker's process.
3. **A rogue listener on port 9999** — a Python script accepting connections on port 9999 and receiving the exfiltrated data. This is the attacker's collection point.

Your job is to use `tcpdump` to capture and analyze the suspicious traffic, kill both rogue processes (client and listener), preserve the legitimate service, and write an incident report documenting your findings.

## Thought Process

When investigating suspicious network activity, an experienced engineer approaches it like an incident response:

1. **Observe first, act second** — use `tcpdump` to capture the suspicious traffic before you do anything. You want evidence of what's happening before you disrupt it.
2. **Identify the processes** — use `ss -tnp` and `ps aux` to find which processes are involved.
3. **Kill the rogue processes** — stop both ends of the suspicious connection (client and listener).
4. **Verify the legitimate service is unaffected** — make sure you didn't break anything that should be running.
5. **Document everything** — write an incident report with your findings. In the real world, this documentation is critical for post-incident review and potentially for legal proceedings.

## Step-by-Step Solution

### Step 1: Capture suspicious traffic with tcpdump

```bash
tcpdump -i lo port 9999 -n -c 10
```

**What this does:** Captures network traffic on the loopback interface (`lo`) filtered to port 9999. Here's what each flag means:
- `-i lo` — capture on the loopback interface (localhost traffic)
- `port 9999` — only capture packets involving port 9999
- `-n` — don't resolve hostnames (faster and shows raw IPs)
- `-c 10` — stop after capturing 10 packets

You'll see a pattern of connections happening every 3 seconds — a client connecting to port 9999, sending data, and disconnecting. This is the exfiltration in action.

### Step 2: Capture the actual data being sent

```bash
tcpdump -i lo port 9999 -n -A -c 5
```

**What this does:** Same capture, but with the `-A` flag which prints the packet payload in ASCII. You'll see the text "EXFIL DATA PACKET" in the captured data, confirming this is data being exfiltrated. The `-A` flag is crucial for seeing the actual content of the traffic.

### Step 3: Identify the processes involved

```bash
ss -tnp | grep 9999
```

**What this does:** Shows all TCP connections involving port 9999 and the processes responsible. The `-t` flag is TCP only, `-n` is numeric, and `-p` shows the process. You'll see two sides: a process listening on port 9999 (the collector) and a process connecting to it (the exfiltrator).

### Step 4: Get full details on the rogue processes

```bash
lsof -i :9999
```

**What this does:** Shows all processes with connections to port 9999, including their PIDs, user, and the connection state. This gives you the PIDs you need to kill and the information for your incident report.

### Step 5: Verify the legitimate service before taking action

```bash
curl -s http://localhost:8080
```

**What this does:** Confirms the legitimate web server is running and responding with "OK." We want to make sure it's working before we start killing processes, so we can verify it's still working afterward.

### Step 6: Kill the rogue exfiltration client

```bash
pkill -f "EXFIL"
```

**What this does:** Kills the Python process that contains "EXFIL" in its command line — the client that's sending data to port 9999. The `-f` flag matches against the full command line.

### Step 7: Kill the rogue listener on port 9999

```bash
pkill -f "9999"
```

Or more precisely:

```bash
kill $(lsof -i :9999 -t)
```

**What this does:** Kills the listener process that was accepting connections on port 9999. We need to kill both ends — the sender and the receiver — to fully stop the exfiltration.

### Step 8: Verify both rogue processes are gone

```bash
ss -tlnp | grep 9999
pgrep -f "EXFIL"
```

**What this does:** Confirms that nothing is listening on port 9999 anymore and no exfiltration process is running. Both commands should return empty output.

### Step 9: Verify the legitimate service is still running

```bash
curl -s http://localhost:8080
```

**What this does:** Confirms the legitimate web server is still running and responding normally. This is critical — your incident response shouldn't cause additional outages.

### Step 10: Write the incident report

```bash
cat > /tmp/incident-report.txt << 'EOF'
INCIDENT REPORT — Suspicious Network Activity
===============================================

Date: $(date)
Analyst: Lab participant

SUMMARY:
A rogue process was discovered exfiltrating data over TCP port 9999 on the
loopback interface. The process was sending packets containing "EXFIL DATA
PACKET" to a local listener every 3 seconds.

FINDINGS:
1. A Python process was connecting to 127.0.0.1:9999 every 3 seconds and
   sending data labeled "EXFIL DATA PACKET"
2. A second Python process was listening on port 9999 and accepting these
   connections, acting as the data collection point
3. The legitimate web service on port 8080 was not affected

EVIDENCE:
- tcpdump capture showed regular TCP connections to port 9999 with ASCII
  payload containing "EXFIL DATA PACKET"
- ss/lsof confirmed the source and destination processes

ACTIONS TAKEN:
1. Captured network traffic using tcpdump for evidence
2. Identified rogue client and listener processes using ss and lsof
3. Terminated both rogue processes (exfiltration client and listener)
4. Verified legitimate services were unaffected

RECOMMENDATIONS:
1. Investigate how the rogue processes were installed
2. Check for persistence mechanisms (crontabs, systemd services, rc.local)
3. Review system for other indicators of compromise
4. Implement egress filtering to prevent unauthorized outbound connections
5. Set up network monitoring alerts for unusual traffic patterns
EOF
```

**What this does:** Creates a formal incident report documenting what was found, what evidence was gathered, what actions were taken, and recommendations for preventing future incidents. In the real world, this documentation is essential for post-incident reviews, management reporting, and potentially legal proceedings.

## Docker Lab vs Real Life

- **tcpdump scope:** In this lab, we capture on the loopback interface (`-i lo`) because the suspicious traffic is between two processes on the same host. On a real server, you'd capture on the external interface (`-i eth0` or `-i any` for all interfaces) and filter for suspicious external destinations.
- **Saving captures:** In production, you'd save the capture to a file with `tcpdump -w /tmp/capture.pcap` and analyze it later with Wireshark (a graphical packet analysis tool). PCAP files are standard evidence in incident response.
- **Full incident response:** In the real world, this would trigger a full incident response process: containment, eradication, recovery, and lessons learned. You'd also check for lateral movement, persistence mechanisms (cron jobs, systemd services, backdoors), and other compromised systems.
- **Network monitoring:** Production environments use tools like Zeek (formerly Bro), Suricata, or cloud-native tools (VPC Flow Logs, GuardDuty) for continuous network monitoring. tcpdump is a tactical tool for investigation, not a monitoring solution.
- **Legal considerations:** In a real incident, you'd preserve evidence carefully (chain of custody), notify the security team, and potentially involve law enforcement. Don't destroy evidence by killing processes before capturing the traffic.

## Key Concepts Learned

- **`tcpdump` is the essential packet capture tool** — it lets you see exactly what's happening on the network at the packet level
- **`-A` flag shows packet content in ASCII** — critical for seeing what data is actually being transmitted
- **Observe before acting** — capture evidence of suspicious activity before killing processes. You can't un-kill a process to investigate it.
- **Kill both ends of a connection** — in an exfiltration scenario, there's a sender and a receiver. Kill both to fully stop the activity.
- **Document everything** — incident reports are critical for post-incident review, improving security posture, and maintaining an audit trail

## Common Mistakes

- **Killing processes before capturing evidence** — once you kill the rogue processes, you lose the ability to observe their behavior. Always capture traffic first.
- **Only killing one end** — if you kill the listener but leave the client running (or vice versa), the remaining process might still be doing damage or could reconnect to a different endpoint.
- **Killing the legitimate service by accident** — not carefully checking which process is which before killing. Always verify the legitimate services first.
- **Not writing the incident report** — in a real incident, documentation is as important as the technical response. Without it, the organization can't learn from the incident or prove what happened.
- **Not checking for persistence** — in a real attack, the rogue process might be configured to restart automatically (via cron, systemd, or rc.local). Killing it once might not be enough — you'd need to find and remove the persistence mechanism.
