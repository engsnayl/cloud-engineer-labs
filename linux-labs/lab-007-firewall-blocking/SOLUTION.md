# Lab 07 — Firewall Blocking Application Ports

## TLDR Summary

Two apps are running perfectly on this machine, but nobody can reach them. The culprit is the Linux firewall (`iptables`). It's set to silently drop all incoming traffic by default, and nobody has added rules to let traffic through to the application ports (8080 and 8081). The fix is to add two targeted rules — one per port — that explicitly allow traffic in. You're not changing the security posture of the firewall; you're just punching two precisely-sized holes in it for the traffic that's supposed to be there.

---

## The Scenario — What You've Been Handed

You receive a ticket. It says something like:

> *"App team is reporting that the web application and its health check endpoint are unreachable. Deployments look healthy from their side. Can you investigate?"*

You're an engineer. You've just sat down at the terminal. You don't yet know whether this is a dead process, a misconfigured app, a networking problem, or a firewall issue. Your job is to figure that out — systematically.

---

## Step-by-Step Investigative Learning Pathway

### Step 1 — Is anything even running?

Before you touch the network or the firewall, you need to answer the most basic question: **is the application process actually alive and listening on a port?**

If the process has crashed, no amount of firewall work will help. You always eliminate "is it even running?" first.

```bash
ss -tlnp
```

**Command breakdown — what each part does:**

| Flag | What it means |
|------|---------------|
| `ss` | The "socket statistics" tool — shows active network sockets on the machine |
| `-t` | Show only **TCP** sockets (filter out UDP) |
| `-l` | Show only **listening** sockets — i.e. servers waiting for incoming connections |
| `-n` | Show **numeric** port numbers instead of trying to resolve them to service names (faster, unambiguous) |
| `-p` | Show the **process** that owns each socket (PID and name) |

**What you're looking for:** Entries showing that something is listening on port 8080 and port 8081.

**What the output tells you:**
- If you see both ports listed → the apps are alive, the problem is downstream (network, firewall)
- If a port is missing → the application itself has failed; the firewall is irrelevant until you fix that first

> In this lab, you will see both ports. The apps are fine. The firewall is the problem.

---

### Step 2 — Try to reach the app yourself (confirm it's blocked, not just slow)

Now you know the process is running. Let's prove the traffic is being blocked rather than just guessing. Try to reach it directly from the machine itself:

```bash
curl -s --connect-timeout 2 http://localhost:8080
```

**Command breakdown:**

| Part | What it means |
|------|---------------|
| `curl` | A command-line HTTP client — sends a request and prints the response |
| `-s` | **Silent** mode — suppresses the progress bar so the output is clean |
| `--connect-timeout 2` | Give up after **2 seconds** if no connection is established — without this, a DROP firewall rule causes curl to hang indefinitely |
| `http://localhost:8080` | The address to connect to — `localhost` means "this machine", port 8080 |

**What you're looking for:**
- If curl hangs or times out → traffic is being **dropped** (firewall DROP rule — packets just vanish)
- If curl returns "Connection refused" → the port is **closed** (nothing listening there)
- If curl returns a response → it's working fine and the problem is elsewhere

> In this lab, curl times out or gets nothing — because the firewall is dropping packets to 8080.

---

### Step 3 — Inspect the firewall

You've now confirmed: app is running, but traffic doesn't get through. Time to look at the firewall rules.

```bash
iptables -L INPUT -n --line-numbers
```

**Command breakdown:**

| Part | What it means |
|------|---------------|
| `iptables` | The Linux firewall management tool |
| `-L INPUT` | **List** all rules in the **INPUT** chain — this chain controls all traffic coming *into* the machine |
| `-n` | Show **numeric** addresses and port numbers (don't resolve to hostnames — faster and avoids DNS delays) |
| `--line-numbers` | Number each rule so you can reference them precisely |

**What you're looking for and what it means:**

Read the output top to bottom. iptables processes rules in order — the first rule that matches a packet wins. If no rule matches, the **default policy** (shown at the top) is applied.

You'll see something like:

```
Chain INPUT (policy DROP)
num  target     prot  source    destination
1    ACCEPT     all   0.0.0.0/0 0.0.0.0/0   state RELATED,ESTABLISHED
2    ACCEPT     tcp   0.0.0.0/0 0.0.0.0/0   tcp dpt:22 -- lo
```

Breaking down what you're seeing:

- **`policy DROP`** — This is the key. Any packet that doesn't match an explicit rule gets dropped silently. This is the "deny by default" security model.
- **Rule 1** — Allows traffic for connections that are already established. This is how responses to outbound requests get back in (e.g. when you run `apt-get`, the response traffic is allowed back).
- **Rule 2** — Allows SSH (port 22) on the loopback interface so you can still get in over SSH.
- **No rule for 8080 or 8081** — This is the problem. The firewall doesn't know it's supposed to let traffic through to these ports.

> This confirms the diagnosis: the firewall has a DROP-all default, and nobody has added ACCEPT rules for the application ports.

---

### Step 4 — Add a rule to allow traffic to port 8080

Now you know the problem. The fix is targeted: add an ACCEPT rule for port 8080.

```bash
iptables -A INPUT -i lo -p tcp --dport 8080 -j ACCEPT
```

**Command breakdown:**

| Part | What it means |
|------|---------------|
| `iptables` | The firewall management tool |
| `-A INPUT` | **Append** a new rule to the end of the INPUT chain |
| `-i lo` | Only match traffic arriving on the **lo**opback interface (i.e. `localhost` — traffic from the machine to itself) |
| `-p tcp` | Only match **TCP** protocol traffic |
| `--dport 8080` | Only match traffic headed to **destination port** 8080 |
| `-j ACCEPT` | **Jump** to the ACCEPT action — let the packet through |

**Why `-i lo`?** In this lab we're testing with `curl localhost`, which goes over the loopback interface. In production on a real server receiving external traffic, you'd either specify the external network interface (e.g. `-i eth0`) or omit `-i` entirely to match any interface.

**Why not just set the default policy to ACCEPT?** That would disable the firewall entirely — everything would be allowed through, not just port 8080. Always add specific rules for the ports that need access. Don't dismantle the fence because you need to open one gate.

---

### Step 5 — Add a rule to allow traffic to port 8081

The health check endpoint runs on a different port. Each port needs its own rule — the firewall doesn't assume that two things on the same host should have the same access policy.

```bash
iptables -A INPUT -i lo -p tcp --dport 8081 -j ACCEPT
```

Same pattern as Step 4, with `--dport 8081` instead. Same logic applies.

---

### Step 6 — Verify the rules were added correctly

Before you test, confirm that what you think you did actually happened:

```bash
iptables -L INPUT -n --line-numbers
```

Same command as Step 3. You should now see two new ACCEPT rules at the bottom of the list — one for port 8080, one for port 8081. The default policy should still say **DROP**. If it now says ACCEPT, something went wrong.

---

### Step 7 — Test the fix

Now try reaching both services:

```bash
curl -s http://localhost:8080
curl -s http://localhost:8081
```

**What you're looking for:**
- Port 8080 should return: `App OK`
- Port 8081 should return: `Healthy`

If you get responses, the fix worked. The firewall is now allowing traffic to these two specific ports while still dropping everything else.

---

## Real-World Context — How This Differs From Production

### iptables vs nftables

In this lab we use `iptables`, the classic Linux firewall tool. Modern Linux distributions are increasingly using `nftables` (the `nft` command), which has cleaner syntax and better performance at scale. Many distros still provide `iptables` as a compatibility layer on top of `nftables`. You'll encounter both in the wild.

### Firewall persistence — the thing that catches people out

The rules you added exist **only in memory**. If the machine reboots, they're gone. On a real server:

- **Debian/Ubuntu:** `iptables-save > /etc/iptables/rules.v4` — saves rules to a file that gets reloaded on boot
- **Red Hat/CentOS with firewalld:** `firewall-cmd --permanent --add-port=8080/tcp` followed by `firewall-cmd --reload`

In a cloud environment like AWS, you'd typically use **Security Groups** instead — these operate at the network level outside the instance and are stateful, persistent, and much easier to audit.

### Cloud security groups vs iptables

On AWS, the equivalent of what you've just done is adding an inbound rule to a Security Group:
- Allow TCP on port 8080 from 0.0.0.0/0 (or a more restricted CIDR)

Security Groups are the first line of defence in AWS — they stop traffic before it even reaches the instance. iptables on the host is a second layer. In a well-architected cloud environment, you'd typically manage access at the Security Group level unless you need host-level granularity.

### Loopback vs external interfaces

In this lab, the `-i lo` flag scopes the rule to loopback (localhost) traffic because we're testing with `curl localhost`. In a real deployment where clients connect from the internet or your network, you'd allow traffic on the external interface — either a specific one (e.g. `-i eth0`) or all interfaces (by omitting `-i` entirely).

---

## Key Concepts

- **Default DROP policy** means nothing gets through unless explicitly allowed. This is the correct, secure default — don't change it, add specific rules instead.
- **iptables processes rules top to bottom** — the first matching rule wins. If nothing matches, the default policy applies.
- **Always verify the process is running before blaming the firewall** — `ss -tlnp` tells you whether the app is actually listening. A dead process is a different problem.
- **`--connect-timeout` in curl is essential** when testing against a DROP firewall — without it, curl hangs indefinitely because the packets are dropped silently (no RST/rejection is sent back).
- **One rule per port** — the firewall requires explicit, specific rules. It doesn't infer that related services should share policies.

---

## Common Mistakes

**Setting the default policy to ACCEPT** — this removes all firewall protection. The lab specifically requires keeping the DROP policy. If you did this, you've "fixed" the symptom by disabling the firewall entirely.

**Running `iptables -F` (flush)** — this deletes all rules. Because the default policy is still DROP, you've now locked out everything including SSH. On a remote server this is catastrophic — you lose your connection and can't get back in without console access.

**Forgetting port 8081** — there are two services. Each needs its own rule. Validation will check both.

**Not running `ss -tlnp` first** — if the app has crashed, adding firewall rules accomplishes nothing. Always confirm the process is listening before touching the firewall.

**Adding rules in the wrong position** — if there's an explicit DROP-all rule *before* your ACCEPT rules, your rules are unreachable. Use `iptables -I INPUT 1` (insert at position 1) to put a rule at the top when ordering matters.

---

## Cleanup / Reset

To reset the lab to its broken starting state:

```bash
# Remove the two ACCEPT rules you added (by port number — check line numbers first with iptables -L INPUT -n --line-numbers)
iptables -D INPUT -i lo -p tcp --dport 8080 -j ACCEPT
iptables -D INPUT -i lo -p tcp --dport 8081 -j ACCEPT
```

After running these, `iptables -L INPUT -n --line-numbers` should show only the original two rules, with policy DROP still in place. The apps will be unreachable again and you can run through from Step 1.
