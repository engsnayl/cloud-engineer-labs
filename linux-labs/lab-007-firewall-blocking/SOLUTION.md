# Solution Walkthrough — Firewall Blocking

## The Problem

Two web applications are running and healthy, but nobody can reach them because the firewall (iptables) is blocking all incoming traffic to their ports. Here's the situation:

1. **A web application is listening on port 8080** — it's running fine and would respond if traffic could reach it.
2. **A health check endpoint is listening on port 8081** — also running fine but unreachable.
3. **The iptables firewall has a default DROP policy on the INPUT chain** — this means any incoming traffic that doesn't match an explicit ALLOW rule gets silently dropped. The only rules currently in place allow established/related connections and SSH on the loopback interface. There are **no rules allowing traffic to ports 8080 or 8081**.

The challenge is to allow traffic to the application ports **without weakening the firewall**. You can't just set the default policy to ACCEPT — that would defeat the purpose of having a firewall. You need to add specific, targeted rules.

## Thought Process

When an application is running but unreachable, an experienced engineer checks things in layers:

1. **Is the process actually running and listening?** Use `ss -tlnp` or `netstat -tlnp` to verify the application is bound to the expected port. If the process isn't listening, the problem is the application, not the network.
2. **Is the firewall blocking it?** Check `iptables -L INPUT -n --line-numbers` to see the current rules and the default policy. If the default policy is DROP and there's no ACCEPT rule for your port, that's your answer.
3. **Add targeted rules** — don't open everything up. Add specific rules for only the ports that need to be accessible, and keep the restrictive default policy.

The key insight is that iptables processes rules top-to-bottom — the first matching rule wins. If no rule matches, the default policy applies. With a default policy of DROP, you must have explicit ACCEPT rules for every port you want to be reachable.

## Step-by-Step Solution

### Step 1: Verify the applications are running and listening

```bash
ss -tlnp
```

**What this does:** Shows all TCP sockets that are in a listening state. The flags mean:
- `-t` — show TCP sockets only
- `-l` — show only listening sockets (servers waiting for connections)
- `-n` — show port numbers instead of service names
- `-p` — show the process using each socket

You should see entries for ports 8080 and 8081, confirming the apps are running fine. The problem is the firewall, not the applications.

### Step 2: Check the current firewall rules

```bash
iptables -L INPUT -n --line-numbers
```

**What this does:** Lists all rules in the INPUT chain (which controls incoming traffic). The `-n` flag shows numeric addresses instead of trying to resolve hostnames (which is faster). The `--line-numbers` flag numbers each rule so you can reference them. You'll see:
- The default policy is **DROP** (shown at the top)
- Rule 1: ACCEPT established/related connections
- Rule 2: ACCEPT TCP port 22 (SSH) on loopback
- No rules for ports 8080 or 8081

### Step 3: Try to reach the app (to confirm it's blocked)

```bash
curl -s --connect-timeout 2 http://localhost:8080
```

**What this does:** Tries to connect to the application with a 2-second timeout. The `-s` flag silences the progress bar. This will time out or fail because the firewall is dropping the packets. This step confirms the diagnosis.

### Step 4: Add a firewall rule to allow traffic to port 8080

```bash
iptables -A INPUT -i lo -p tcp --dport 8080 -j ACCEPT
```

**What this does:** Adds a new rule to the INPUT chain that allows incoming TCP traffic to port 8080 on the loopback interface. Here's what each part means:
- `-A INPUT` — **A**ppend a rule to the INPUT chain
- `-i lo` — only match traffic on the **lo**opback interface (localhost)
- `-p tcp` — only match **TCP** protocol traffic
- `--dport 8080` — only match traffic headed to **d**estination **port** 8080
- `-j ACCEPT` — **j**ump to the ACCEPT target (allow the traffic through)

### Step 5: Add a firewall rule to allow traffic to port 8081

```bash
iptables -A INPUT -i lo -p tcp --dport 8081 -j ACCEPT
```

**What this does:** Same as the previous step, but for port 8081 (the health check endpoint). Each port needs its own rule — firewalls are explicit about what they allow.

### Step 6: Verify the new rules are in place

```bash
iptables -L INPUT -n --line-numbers
```

**What this does:** Shows the updated rule list. You should now see your two new ACCEPT rules for ports 8080 and 8081, and the default policy should still be DROP.

### Step 7: Test that the applications are now reachable

```bash
curl -s http://localhost:8080
curl -s http://localhost:8081
```

**What this does:** Sends HTTP requests to both application ports. You should now get responses — "App OK" from port 8080 and "Healthy" from port 8081. The firewall is now allowing traffic to these specific ports while still blocking everything else.

## Docker Lab vs Real Life

- **iptables vs nftables:** In this lab we use `iptables`, which is the classic Linux firewall tool. Modern Linux distributions are transitioning to `nftables` (with the `nft` command), which has cleaner syntax and better performance. Many distros still provide `iptables` as a compatibility layer on top of nftables.
- **Firewall persistence:** In this lab, our iptables rules exist only in memory — they'd be lost on reboot. On a real server, you'd use `iptables-save > /etc/iptables/rules.v4` (Debian/Ubuntu) or `firewall-cmd --permanent` (Red Hat/CentOS with firewalld) to persist rules across reboots.
- **Security groups vs iptables:** On cloud platforms like AWS, you'd typically use Security Groups (which operate at the network level outside the instance) rather than iptables on the host. Security groups are stateful and easier to manage. However, iptables is still used for more granular control or when running on bare metal.
- **Loopback vs all interfaces:** In this lab we add rules for the loopback interface (`-i lo`) because we're testing with `curl localhost`. On a real server, you'd allow traffic on the external interface (e.g., `-i eth0`) or omit the `-i` flag entirely to allow traffic from any interface.

## Key Concepts Learned

- **Default DROP policy is secure but requires explicit ALLOW rules** — anything not explicitly permitted is denied. This is the "deny by default" security model.
- **`iptables -L INPUT -n --line-numbers` is your diagnostic command** for seeing exactly what the firewall is doing
- **Rules are processed in order** — iptables checks each rule from top to bottom and applies the first one that matches. If nothing matches, the default policy applies.
- **Always verify apps are running before blaming the firewall** — use `ss -tlnp` to confirm the process is actually listening on the expected port
- **Be specific with firewall rules** — allow only the ports and interfaces needed, don't open everything up just to make something work

## Common Mistakes

- **Setting the default policy to ACCEPT** — this "fixes" the problem by removing all firewall protection. The challenge specifically requires keeping the DROP policy. Always add targeted rules instead.
- **Using `iptables -F` (flush all rules)** — this deletes all rules but the default policy stays DROP, which would lock you out of everything, including SSH on a remote server. Extremely dangerous in production.
- **Forgetting to allow both ports** — there are two services (8080 and 8081), and each needs its own rule.
- **Not verifying the apps are running first** — if the application itself has crashed, adding firewall rules won't help. Always confirm the process is listening before modifying iptables.
- **Adding rules but in the wrong position** — if there's a catch-all DROP rule before your ACCEPT rules, your rules will never be reached. Use `iptables -I INPUT 1` (insert at position 1) if you need a rule to take priority over existing ones.
