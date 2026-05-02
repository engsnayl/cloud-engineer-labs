# Lab 052 — Log Aggregation Pipeline Broken

## TLDR (Plain English)

Logs from this server are supposed to be flowing to a central log collector, but nothing is arriving. When you investigate, you find **two things wrong at the same time**:

1. **The log forwarding service (rsyslog) isn't actually running.** Someone configured it to forward logs, but never started it. The config file is sitting there doing nothing because there's no process reading it.
2. **Even if it were running, it would forward to the wrong place.** The config says "send logs to port 5515" but the collector is actually listening on port 5514. One digit off, and every message gets sent into the void with no error.

**The fix is two steps:** correct the port number in the config file (5515 → 5514), then start the rsyslog daemon. After that, send a test log with `logger` and confirm it appears in `/var/log/aggregated.log`.

**Why this is a sneaky bug:** UDP is "fire and forget" — when rsyslog sends to a port nobody's listening on, you get no error, no warning, no rejection. The packet just disappears. This is one of the classic gotchas of UDP-based log forwarding.

---

## The Ticket

> **INCIDENT-MON-003**: No logs from app-server-03 in central logging for 48 hours. Rsyslog is installed but forwarding appears broken. Need to fix the log pipeline.

You've been handed a ticket. That's all you know. No one has told you about port numbers, no one has told you whether rsyslog is running, no one has told you what's in the config files. Time to investigate.

---

## Arriving Cold — What Do I Even Look At First?

When a log forwarding pipeline isn't working, there are essentially **four things** that could be broken, and they map to the four stages a log message has to travel through:

```
[ application ]  →  [ rsyslog daemon ]  →  [ network ]  →  [ aggregator listening ]
       1                     2                  3                     4
```

If any one of those stages is broken, no logs arrive. So the diagnostic strategy is: **walk the pipeline from one end to the other and check each stage in turn.**

The natural order to check them is:

1. **Is the forwarder process running at all?** (cheapest check — one command)
2. **What does the forwarder think it should be doing?** (read the config)
3. **Is the destination actually listening where the config points?** (check the port)
4. **Does an end-to-end test message make it through?** (the proof)

That's the play. Now let's run it.

---

## Step 1 — Get into the container and orient yourself

```bash
docker exec -it lab052-log-aggregation-broken bash
```

**What's happening:** You're opening an interactive shell inside the running container. The `-it` flag combination is two things — `-i` keeps stdin open (so you can type), `-t` allocates a pseudo-TTY (so the shell behaves like a normal terminal with prompts).

Once you're inside, your prompt should change to `root@<container-id>:/#`. You're now *on* the broken server.

### How would I know what to investigate first?

The ticket says "rsyslog is installed but forwarding appears broken." So rsyslog is your prime suspect. Before reading any config files, ask the cheapest possible question first: **is it even running?**

---

## Step 2 — Check if rsyslog is running

```bash
pgrep rsyslog
```

**What's happening:** `pgrep` searches the list of running processes for ones whose name matches `rsyslog`. If it finds any, it prints their process IDs (PIDs). If it finds none, it prints nothing and exits with a non-zero status.

| Component | What it does |
|---|---|
| `pgrep` | "process grep" — find processes by name |
| `rsyslog` | the pattern to match against process names |

**What you'll see:** Nothing. The command returns no output.

### How do I interpret silence?

Silence from `pgrep` means **no process matching that name is running**. That's already a huge clue. The rsyslog daemon — the thing that's supposed to be reading the config and forwarding logs — isn't even running. No process means no forwarding, regardless of what any config file says.

**Bug #1 found:** rsyslog daemon is not running.

### What about `service rsyslog status`?

In a real EC2 instance you'd typically use `systemctl status rsyslog` or `service rsyslog status` as a more informative status check. **In this minimal container neither works** — you'll get `rsyslog: unrecognized service`. The reason is that this container doesn't have systemd, and the rsyslog package was installed without registering an init script in `/etc/init.d/`. That's normal for stripped-down container images.

So in this lab, `pgrep rsyslog` is your only "is it running?" check. See the **Lab vs Real Life** table at the bottom for the full mapping.

### Should I just start it now?

You *could*, but don't yet. If you start rsyslog right now, it'll read whatever's in the config file and start forwarding to wherever the config says. If the config is wrong, you'll have started a process that confidently forwards messages to a dead end. Better to verify the config first, fix anything wrong, *then* start the service. One round of debugging instead of two.

---

## Step 3 — Read the forwarding configuration

```bash
ls /etc/rsyslog.d/
```

**What's happening:** Listing the contents of the rsyslog config drop-in directory. Rsyslog reads its main config from `/etc/rsyslog.conf`, but it also pulls in any `.conf` files from `/etc/rsyslog.d/`. This is the standard place for custom forwarding rules to live.

You'll see:
```
50-default.conf
50-forwarding.conf
```

The `50-forwarding.conf` is the interesting one — the name itself tells you it's about forwarding. Open it:

```bash
cat /etc/rsyslog.d/50-forwarding.conf
```

You'll see:

```
# Forward all logs to central aggregation
*.* @127.0.0.1:5515
```

### How do I read this line?

This is rsyslog's forwarding syntax. Breaking it down:

| Part | Meaning |
|---|---|
| `*.*` | "All facilities, all severities" — match every log message |
| `@` | Forward over **UDP** (one `@`). Two `@@` would mean TCP. |
| `127.0.0.1` | The destination host — localhost in this case |
| `:5515` | The destination port |

So this line says: *"For every log message, send it via UDP to localhost on port 5515."*

The question now is: **is port 5515 actually where the aggregator is listening?** That's the next check.

---

## Step 4 — Find out where the aggregator is actually listening

This is the step that catches the second bug. The config *claims* the aggregator is on 5515. Trust nothing — verify.

```bash
netstat -ulnp
```

**What's happening:** `netstat` shows network sockets. We're asking it to show only the listening UDP sockets along with which process is holding each one.

| Flag | What it does |
|---|---|
| `-u` | UDP sockets only (because rsyslog is forwarding via `@` = UDP) |
| `-l` | Listening sockets only (things waiting for connections) |
| `-n` | Numeric output — show port numbers, not service names |
| `-p` | Show the process holding each socket |

**What you'll see:**

```
Active Internet connections (only servers)
Proto Recv-Q Send-Q Local Address     Foreign Address      State    PID/Program name
udp        0      0 0.0.0.0:5514      0.0.0.0:*                     8/python3
udp        0      0 127.0.0.11:42981  0.0.0.0:*                     -
```

### What is this telling me?

Two UDP listeners, but only one is interesting:

- **`0.0.0.0:5514` held by `python3`** — that's the fake aggregator from the lab setup. It's bound to all interfaces (`0.0.0.0`) on port 5514. **This is the truth — the aggregator is on 5514, not 5515.**
- **`127.0.0.11:42981`** — Docker's internal DNS resolver. Always present, irrelevant to our investigation. Worth recognising so you don't get distracted by it in real container debugging.

**But the rsyslog config says forward to 5515.** The aggregator is on 5514. **Off by one digit.**

**Bug #2 found:** the forwarding config points to the wrong port.

### Why aren't we using `ss`?

On a modern EC2 host you'd use `ss -ulnp` instead — it's the modern replacement for `netstat`, faster on busy systems, and is the canonical command in any modern troubleshooting guide. But this minimal container doesn't have `ss` installed (it ships in the `iproute2` package, which wasn't pulled in). The diagnostic *intent* — "show me what's listening on UDP" — is identical; the tool changes based on what's available.

### How would I have known to check this in real life?

In production, you'd cross-reference the rsyslog config against whatever runbook or wiki entry documents the central logging service. ("Our log aggregator listens on UDP 5514" should be written down somewhere.) But even without docs, `netstat -ulnp` (or `ss -ulnp`) tells you the truth — what's *actually* bound and listening on this host. The config tells you what someone *thought* should happen; netstat tells you what's real. When the two disagree, real wins.

### Why didn't UDP throw an error about this?

UDP is connectionless. When rsyslog sends a packet to 127.0.0.1:5515 and nothing is listening there, the packet is just dropped silently. No "connection refused", no error, no nothing. With TCP (`@@` instead of `@`) you'd get a refused connection and rsyslog would log an error. With UDP, you only find out by checking like this.

This is one of the most important real-world lessons in this lab: **silent failures are the worst failures**, and UDP-based pipelines are full of them.

---

## Step 5 — Fix the port

Now you know what's wrong. Fix the config. Either tool works:

**Option A — `sed` (one-liner):**

```bash
sed -i 's/5515/5514/' /etc/rsyslog.d/50-forwarding.conf
```

| Part | Meaning |
|---|---|
| `sed` | "stream editor" — manipulates text |
| `-i` | "in place" — write changes back to the file directly |
| `'s/5515/5514/'` | the substitution: `s` = substitute, then `/old/new/` |
| `/etc/rsyslog.d/50-forwarding.conf` | the file to edit |

**Option B — `vi` (interactive):**

```bash
vi /etc/rsyslog.d/50-forwarding.conf
# move to the line, press 'x' over the '5', type 'i' to insert '4', then ':wq' to save
```

`sed` is faster for one-character changes; `vi` is better when you want to read the whole file in context first. Both are valid. In real incident response, whichever feels more natural — speed of fix matters when you're under pressure.

Verify the change either way:

```bash
cat /etc/rsyslog.d/50-forwarding.conf
```

You should now see:
```
# Forward all logs to central aggregation
*.* @127.0.0.1:5514
```

---

## Step 6 — Start rsyslog

Both bugs are now addressed in the right order: the config is correct, *now* start the service.

In a real EC2 environment, you'd run `systemctl start rsyslog` or `service rsyslog start`. In this container, neither works (no systemd, no init script). You start the daemon binary directly:

```bash
rsyslogd
```

**What's happening:** `rsyslogd` is the actual rsyslog daemon executable. Run it with no arguments and it will fork into the background and start reading `/etc/rsyslog.conf` plus everything in `/etc/rsyslog.d/`. This is the real binary that `service` or `systemctl` would invoke under the hood; we're just calling it directly because there's no init system in this container to do it for us.

### Expected warning — totally harmless

You'll likely see this warning:

```
rsyslogd: imklog: cannot open kernel log (/proc/kmsg): Operation not permitted.
rsyslogd: activation of module imklog failed [v8.2112.0 try https://www.rsyslog.com/e/2145 ]
```

**This is normal in unprivileged containers and does NOT affect log forwarding.**

`imklog` is rsyslog's *kernel log input module* — it reads kernel ring buffer messages from `/proc/kmsg`. Doing so requires the `CAP_SYSLOG` capability, which Docker containers don't get by default (and quite reasonably so — you don't want random containers reading the host kernel's logs). So `imklog` fails to load, rsyslog logs the failure, and **continues starting up anyway**.

The forwarding module — which is what we actually care about — loads fine. Our test path is `logger` → local syslog socket → rsyslog → UDP forward → aggregator, none of which touches kernel logs.

Verify the daemon is running:

```bash
pgrep rsyslog
```

You should now see one or more PIDs printed. Service is up.

---

## Step 7 — Test end-to-end

You've checked each stage in isolation. Now prove the whole pipeline works by sending a message through it:

```bash
logger -t test "validation check from $(hostname)"
```

**What's happening:** `logger` is a small command-line utility that injects a message into the syslog system, exactly as if an application had logged it.

| Part | Meaning |
|---|---|
| `logger` | the command itself — "send this to syslog" |
| `-t test` | set the **tag** (the program name field) to "test" — makes the message easy to find |
| `"validation check from $(hostname)"` | the message body. `$(hostname)` is shell command substitution that inserts the container's hostname. |

The message flow you've just triggered:

```
logger  →  local syslog socket  →  rsyslog daemon  →  UDP packet to 127.0.0.1:5514  →  Python aggregator  →  /var/log/aggregated.log
```

Wait a second for the message to travel through, then check the destination:

```bash
sleep 1
cat /var/log/aggregated.log
```

You should see something like:

```
<13>Oct 26 14:32:01 test: validation check from a3f9c2e1b4d7
```

If you see your test message, **the pipeline is working end-to-end.**

### What if it's not there?

Then walk the pipeline backwards:
- Is rsyslog still running? (`pgrep rsyslog`)
- Did the config actually save with the new port? (`cat /etc/rsyslog.d/50-forwarding.conf`)
- Is the aggregator still listening on 5514? (`netstat -ulnp`)
- Is `/var/log/aggregated.log` even writable? (`ls -la /var/log/aggregated.log`)

In this lab there shouldn't be anything else broken, but in real life this kind of methodical "walk the pipeline" check is exactly how you find the third or fourth bug hiding behind the first two.

---

## Step 8 — Confirm with the application logs

The lab also has a log generator script at `/opt/generate-logs.sh` that produces a steady stream of "application" log messages. Start it:

```bash
/opt/generate-logs.sh &
```

The `&` runs it in the background so you get your prompt back. Wait a few seconds, then:

```bash
sleep 5
tail /var/log/aggregated.log
```

You should see a stream of messages tagged `myapp` arriving every 2 seconds. That's the realistic case — a real application generating real logs, all flowing through the now-working pipeline to the aggregator.

---

## Step 9 — Run the validator

```bash
exit                                    # leave the container
lab validate 052
```

The validator checks all six things you've just verified manually:
- Container is running
- Rsyslog daemon is running
- Forwarding config has an active rule pointing to port 5514
- No active forwarding rule still references the broken port 5515
- Aggregator is listening on UDP port 5514
- Test log message arrives at the aggregation endpoint

You should see all six pass.

---

## Step 10 — Cleanup

When you're done, shut the lab container down. From the lab directory:

```bash
cd ~/cloud-engineer-labs/cloud-labs/lab-052-log-aggregation-broken
docker compose down -v
```

| Part | Meaning |
|---|---|
| `docker compose down` | Stop and remove the container defined in `docker-compose.yml` |
| `-v` | Also remove any named or anonymous volumes — wipes the test logs from this run so the next run starts clean |

This is a Docker-only lab — no AWS resources, no costs, no `terraform destroy` needed.

### Resetting the lab to broken state

If you want to run this lab again from a clean broken state:

```bash
docker compose up -d
```

The container rebuilds from the image and re-runs `inject-faults.sh`, putting rsyslog back into "not running, wrong port" state. No `git checkout` needed — the broken state lives in the Dockerfile and `inject-faults.sh`, not in tracked working files.

---

## Real-World Gotcha Log — Things This Container Surprises You With

A clean record of the deviations between this lab's minimal Ubuntu container and a typical real-world Linux host. These are realistic — minimal containers and stripped-down jumphosts behave like this, so building muscle memory for the fallbacks is genuinely useful.

| Canonical command (real EC2) | This container | Why it differs |
|---|---|---|
| `systemctl status rsyslog` | `pgrep rsyslog` | No systemd in the container |
| `service rsyslog status` | `pgrep rsyslog` | Package installed without an init script |
| `service rsyslog start` | `rsyslogd` (run binary directly) | Same — no init script, so call the binary |
| `ss -ulnp` | `netstat -ulnp` | `iproute2` package not installed |
| (no warning) | `imklog: cannot open kernel log` warning on rsyslogd start | `CAP_SYSLOG` not granted to unprivileged containers |

**The general pattern:** when you're on a minimal container, a stripped-down jumphost, or a hardened production server, your usual commands may not be there. Knowing the older fallbacks (`netstat` instead of `ss`, `pgrep` instead of `systemctl status`) is what separates the engineer who can ship a fix in 5 minutes from the one who's stuck SSH'd into a box not knowing what tools they have.

---

## Why This Bug Set Is Realistic

The "two bugs at once" pattern in this lab mirrors something that happens constantly in production:

- Someone deploys a new logging config — let's say from a Terraform module or an Ansible playbook.
- The deploy writes the config file but the service restart step fails or is skipped.
- Nobody notices because UDP forwarding to a wrong port produces no errors.
- Days or weeks later, someone goes looking for logs that should exist and finds nothing.

The combination of *"the daemon never started"* + *"the config was wrong anyway"* is exactly the kind of thing that hides in plain sight, because each problem masks the symptoms of the other. If rsyslog had been running, you'd have seen "no logs arriving" and gone hunting for the port issue. If the port had been right, you'd have seen "no logs arriving" and gone hunting for the daemon. Both broken at once feels the same as either one broken — silence — which is why methodical pipeline-walking is the right approach.

---

## Real-World Context — Beyond rsyslog

In production cloud environments, you'd rarely see rsyslog used in isolation like this. The patterns you'll actually meet:

- **ELK / EFK stacks**: rsyslog forwards to Logstash or Fluentd, which parses, enriches, and ships to Elasticsearch. Kibana sits on top for querying.
- **CloudWatch Logs Agent / Fluent Bit**: in AWS, the CloudWatch agent (or Fluent Bit) replaces or complements rsyslog. Logs flow into CloudWatch Logs and become queryable with CloudWatch Insights.
- **Structured logging (JSON)**: production apps log JSON, not free-text syslog. The forwarder doesn't care, but downstream queries become much easier.
- **TLS encryption**: production forwarding is always over TLS (`@@` with TLS in rsyslog), because logs contain sensitive data — IPs, usernames, error stack traces, sometimes even tokens.
- **Disk-assisted queues**: rsyslog can buffer to disk if the destination is unreachable, then drain the buffer when it recovers. Prevents log loss during aggregator outages.
- **Security group / firewall rules**: in the cloud, the host can be configured perfectly but a security group blocking UDP 5514 will produce the exact same symptom — silent loss. Always check the network path.

The diagnostic mindset, though, is identical at every layer: **walk the pipeline, check each stage, don't trust the config — verify what's actually happening.**

---

## Key Lessons

- **Silent failures are the most dangerous class of bug.** UDP forwarding to a wrong port produces zero error signals. Build the muscle of "verify the destination is listening" as a routine check.
- **Always check the cheapest thing first.** "Is the process even running?" takes one command. Don't read 200 lines of config before you've answered that.
- **`@` is UDP, `@@` is TCP** in rsyslog forwarding syntax. Worth memorising — it's a common gotcha.
- **The config tells you what *should* happen. `netstat` / `ss` tells you what *is* happening.** When they disagree, reality wins.
- **`logger` is your best friend for syslog testing.** It injects a message into the local syslog as if it came from an application — the cleanest way to test forwarding pipelines end-to-end.
- **Walk the pipeline, end to end.** When a multi-stage pipeline isn't working, methodically check each stage in order. It's slower than guessing but catches bugs that hide behind other bugs.
- **Know your fallback commands.** Minimal containers and hardened production hosts often lack the modern tools. `pgrep` instead of `systemctl status`, `netstat` instead of `ss`, `rsyslogd` instead of `systemctl start rsyslog` — these are not legacy junk, they're survival kit.

---

## Common Mistakes

- **Starting rsyslog before fixing the config.** The daemon comes up and confidently forwards to nowhere. You then have to debug a "running but useless" service, which is harder than debugging a stopped one.
- **Trusting the config without verifying with `netstat`/`ss`.** If you'd just read the config and assumed 5515 was correct, you'd have started rsyslog and still seen no logs — and now you'd be hunting a different bug.
- **Panicking at the `imklog` warning.** It's a red herring in containers. Read the message — "kernel log" — and ask "do I need kernel logs forwarded right now?" The answer is no, so move on.
- **Using `@` (UDP) when the destination expects TCP.** UDP loses messages silently; TCP at least tells you when it can't connect. In real production, default to TCP unless throughput pressure forces UDP.
- **Forgetting to test end-to-end after the fix.** Restarting the service isn't proof. Send a `logger` message and watch it arrive — that's proof.
- **Not checking firewall / security group rules.** In cloud environments, this is the third thing to look at after "is rsyslog running" and "is the config right". A security group blocking UDP 5514 looks identical to all the other failure modes.

---

## Pi / K3s Environment Notes

This lab runs entirely inside a Docker container, so there are no Pi-specific or K3s-specific gotchas to worry about. The container is built `FROM ubuntu:22.04` which has multi-arch images including ARM64, so it works fine on the Pi 4 without any platform flags.

No `--platform=linux/amd64` workaround needed.

No cleanup beyond `docker compose down -v` when you're finished — containers are disposable.
