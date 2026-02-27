# Solution Walkthrough — Lab 002: DNS Resolution Failing

## TLDR
DNS is broken three ways. The nameservers in /etc/resolv.conf are rubbish — test them, don't just eyeball them, then replace with 8.8.8.8. After that, dig works but ping doesn't because /etc/nsswitch.conf has been changed to skip DNS lookups — add dns back. Finally, /etc/hosts has the wrong IP for the internal hostname — fix the entry.

## The Problem

DNS (Domain Name System) is what translates human-readable names like `google.com` into IP addresses like `142.250.187.206`. When DNS is broken, almost nothing network-related works — you can't browse the web, you can't call APIs, you can't pull packages.

In this lab, the network team made changes during a maintenance window that broke DNS resolution. There are three separate things wrong, and we'll find each one by *testing* systematically rather than just eyeballing config files.

## Thought Process

When DNS isn't working, there's a simple mental model to follow:

1. **Confirm the symptom** — Is DNS actually broken, or is it something else?
2. **Check what nameservers are configured** — What DNS servers is this machine trying to use?
3. **Test each nameserver individually** — Are they actually responding?
4. **Test with a known-good nameserver** — Is the problem the nameservers, or something deeper?
5. **Check internal hostname mappings** — Are local entries correct?

The key principle: **don't assume something is wrong by looking at it — test it and prove it**.

## Step-by-Step Solution

### Step 1: Confirm that DNS is actually broken

```bash
ping -c 1 google.com
```

**What this does:** `ping` sends a network packet to a host to check if it's reachable. The `-c 1` flag means "send just 1 packet" (without it, ping runs forever).

**What you'll see:**
```
ping: google.com: Temporary failure in name resolution
```

This confirms DNS resolution is failing. The system can't translate `google.com` into an IP address. Let's find out why.

---

### Step 2: Check what nameservers are configured

```bash
cat /etc/resolv.conf
```

**What this does:** `/etc/resolv.conf` is the file that tells Linux which DNS servers to use. `cat` prints the file contents to your terminal.

**What you'll see:**
```
# Updated during maintenance window — network team
nameserver 192.168.999.1
nameserver 10.255.255.254
search localdomain
```

There are two nameservers listed. Are they valid? You might look at the first one and think "that looks like a normal IP address" — but don't trust your eyes. **Test them.**

---

### Step 3: Test the first nameserver

```bash
nslookup google.com 192.168.999.1
```

**What this does:** `nslookup` asks a specific DNS server to resolve a hostname. The format is `nslookup <hostname> <dns-server-ip>`. This lets you test individual nameservers to see which ones work and which ones don't.

**What you'll see:**
```
;; connection timed out; no servers could be reached
```

This nameserver doesn't work. If you look closely at the IP `192.168.999.1`, the third number is `999` — but IP address octets can only go up to `255`. This isn't a valid IP address at all. But the point is: you don't *need* to spot that by eye. The test proved it doesn't work.

---

### Step 4: Test the second nameserver

```bash
nslookup google.com 10.255.255.254
```

**What you'll see:** This will also time out. `10.255.255.254` is a valid-format IP address, but there's no DNS server running there. Again — you proved it by testing, not by guessing.

---

### Step 5: Test with a known-good DNS server

This is the critical diagnostic step. We know both configured nameservers are bad. But is the *network* working? Can this machine reach the internet at all? Let's test with a DNS server we *know* works.

```bash
nslookup google.com 8.8.8.8
```

**What this does:** `8.8.8.8` is Google's free public DNS server. It's one of the most reliable DNS servers in the world. By testing against it, we can prove whether the problem is "bad nameservers" or "no network connectivity at all".

**What you'll see:**
```
Server:         8.8.8.8
Address:        8.8.8.8#53

Non-authoritative answer:
Name:   google.com
Address: 142.250.187.206
```

It works! This tells us two important things:
- The network connection is fine (we can reach the internet)
- DNS resolution works — we just had the wrong nameservers configured

---

### Step 6: Fix resolv.conf

Now we know the nameservers are wrong, so let's replace them with one that works:

```bash
cat > /etc/resolv.conf << 'EOF'
nameserver 8.8.8.8
search localdomain
EOF
```

**What this does:** This overwrites `/etc/resolv.conf` with new contents. We're using `8.8.8.8` (Google's public DNS) as our nameserver.

**What `cat >` means:** The `cat > filename << 'EOF'` pattern is called a "heredoc". It writes everything between the first `EOF` and the last `EOF` into the file. The `>` means "overwrite the file" (as opposed to `>>` which appends).

> **Tip:** You could also use `vim /etc/resolv.conf` to edit the file manually if you prefer. Either approach works.

---

### Step 7: Verify DNS works with dig

```bash
dig google.com
```

**What this does:** `dig` (Domain Information Groper) is the go-to tool for DNS troubleshooting. It queries the nameserver configured in `/etc/resolv.conf` and shows detailed results.

**What you'll see:** A response with an `ANSWER SECTION` showing google.com's IP address, and `status: NOERROR`. This confirms our new nameserver is working.

Now let's test with `ping` to make sure applications can resolve names too:

```bash
ping -c 1 google.com
```

**What you'll see:**
```
ping: google.com: Temporary failure in name resolution
```

Wait — it *still* doesn't work?! But `dig` just worked fine!

---

### Step 8: Understand why dig works but ping doesn't

This is a really important thing to understand. `dig` and `nslookup` are DNS tools — they query DNS servers directly by talking to the nameserver in `/etc/resolv.conf`. They bypass the rest of the system.

But `ping`, `curl`, and normal applications use the system's **name resolution service**, which follows a configuration file that decides *how* to resolve names and *in what order*.

That file is `/etc/nsswitch.conf`. Let's check it:

```bash
cat /etc/nsswitch.conf | grep hosts
```

**What this does:** We're printing the contents of `nsswitch.conf` and filtering for the `hosts:` line, which controls hostname resolution.

**What `grep` does:** `grep` searches for lines matching a pattern. So `grep hosts` shows only lines containing the word "hosts".

**What you'll see:**
```
hosts:          files
```

**What this means:** The `hosts:` line tells Linux the order in which to try resolving hostnames:
- `files` = check `/etc/hosts` first
- `dns` = then query DNS servers

Right now it only says `files` — meaning the system *only* checks `/etc/hosts` and **never queries DNS at all**. That's why `ping` fails even though `dig` works: `dig` talks to DNS directly, but `ping` follows nsswitch.conf's rules.

---

### Step 9: Fix nsswitch.conf

We need to add `dns` back to the hosts line:

```bash
sed -i 's/^hosts:.*/hosts:          files dns/' /etc/nsswitch.conf
```

**What this does:** `sed` is a stream editor that can find and replace text in files.
- `-i` means "edit the file in place" (modify it directly, don't just print the result)
- `'s/pattern/replacement/'` is the substitution syntax
- `^hosts:.*` means "find a line starting with `hosts:` followed by anything"
- `hosts:          files dns` is what we're replacing it with

This restores the normal behaviour: check `/etc/hosts` first, then query DNS.

> **Tip:** You can also just open the file with `vim /etc/nsswitch.conf` and change `hosts: files` to `hosts: files dns` manually.

---

### Step 10: Verify ping now works

```bash
ping -c 1 google.com
```

**What you'll see:**
```
PING google.com (142.250.187.206) 56(84) bytes of data.
64 bytes from lhr25s34-in-f14.1e100.net: icmp_seq=1 ttl=109 time=5.42 ms
```

Excellent! External DNS is fully working now. Applications can resolve hostnames.

---

### Step 11: Check the internal hostname mapping

The ticket says the application needs `payments-api.internal` to resolve to `10.0.1.50`. Internal hostnames like this aren't in public DNS — they're defined locally in `/etc/hosts`. Let's check:

```bash
cat /etc/hosts
```

**What this does:** `/etc/hosts` is a local file that maps hostnames to IP addresses. It's checked *before* DNS (because nsswitch.conf says `files` before `dns`).

**What you'll see:** Among other entries, you'll find:
```
10.0.99.99  payments-api.internal
```

That's the wrong IP. The application needs `10.0.1.50`, not `10.0.99.99`.

---

### Step 12: Fix the /etc/hosts entry

First, remove the wrong entry:

```bash
sed -i '/payments-api.internal/d' /etc/hosts
```

**What this does:** `sed -i` edits the file in place. The `/payments-api.internal/d` pattern means "find any line containing `payments-api.internal` and **d**elete it".

Now add the correct entry:

```bash
echo "10.0.1.50  payments-api.internal" >> /etc/hosts
```

**What this does:** `echo` prints text, and `>>` appends it to the end of the file (double `>>` = append, single `>` = overwrite).

---

### Step 13: Verify the internal hostname resolves correctly

```bash
getent hosts payments-api.internal
```

**What this does:** `getent` queries the system's name resolution (following nsswitch.conf rules). For the `hosts` database, it checks `/etc/hosts` first, then DNS. This is how applications actually resolve names, so it's the most realistic test.

**What you'll see:**
```
10.0.1.50       payments-api.internal
```

That's the correct IP.

---

### Step 14: Final verification — everything works

Let's confirm all resolution paths work:

```bash
# External DNS works
dig +short google.com

# Applications can resolve external names
ping -c 1 google.com

# Internal hostname is correct
getent hosts payments-api.internal
```

**What `dig +short` does:** The `+short` flag tells dig to only print the answer (the IP address), skipping all the verbose DNS metadata. Useful for quick checks.

All three should succeed. You're done!

## Summary of What Was Broken

| Fault | File | What was wrong | How you found it |
|-------|------|---------------|-----------------|
| Bad nameservers | `/etc/resolv.conf` | Invalid IPs (`192.168.999.1` and `10.255.255.254`) | Tested each with `nslookup`, tested known-good `8.8.8.8` |
| DNS lookups disabled | `/etc/nsswitch.conf` | `hosts: files` was missing `dns` | `dig` worked but `ping` didn't — different resolution paths |
| Wrong internal IP | `/etc/hosts` | `payments-api.internal` pointed to `10.0.99.99` instead of `10.0.1.50` | Checked with `cat /etc/hosts` |

## Docker Lab vs Real Life

**resolv.conf:** In this Docker container, we used `8.8.8.8` (Google's public DNS). In a Docker container, the default DNS is `127.0.0.11` (Docker's built-in DNS resolver). On an EC2 instance in AWS, the VPC automatically provides a DNS server at the VPC CIDR base +2 (e.g., if your VPC is `10.0.0.0/16`, the DNS server is `10.0.0.2`). On a real server in a corporate network, you'd use whatever DNS servers your network team provides.

**nsswitch.conf:** This is exactly the same in Docker and in production. It's a real Linux system file that works identically everywhere.

**/etc/hosts:** Same in Docker and production. In real life, you might also use Route 53 Private Hosted Zones or internal DNS for service discovery instead of /etc/hosts entries.

**dig vs ping for testing:** This distinction matters everywhere. `dig` and `nslookup` always query DNS directly. `ping`, `curl`, and applications follow the nsswitch.conf resolution order. Always test with both when debugging DNS issues.

## Key Concepts Learned

- **`/etc/resolv.conf`** controls which DNS servers the system uses
- **`/etc/nsswitch.conf`** controls the *order* of name resolution (files, then DNS, etc.)
- **`/etc/hosts`** provides local hostname-to-IP mappings (checked before DNS)
- **`nslookup <host> <server>`** lets you test a specific DNS server
- **`8.8.8.8`** is Google's public DNS — useful as a known-good reference for testing
- **`dig`** queries DNS directly; **`ping`/`curl`** follow nsswitch.conf rules — they can give different results
- **`getent hosts`** tests resolution the way applications actually do it
- **`sed -i`** edits files in place — useful for quick config fixes
- Always **test, don't assume** — prove something is broken before trying to fix it

## Common Mistakes

- **Eyeballing resolv.conf instead of testing:** `192.168.999.1` looks plausible at a glance. Always test each nameserver individually with `nslookup` rather than trying to spot problems by reading.
- **Stopping after fixing resolv.conf:** When `dig` works after fixing the nameserver, you might think you're done. But if `ping` still fails, there's another layer to check (nsswitch.conf).
- **Not knowing about nsswitch.conf:** This file controls how Linux resolves names. The `hosts:` line is the most commonly relevant part. If `dns` is missing from it, the system ignores DNS entirely.
- **Forgetting to remove the wrong /etc/hosts entry:** If you add the correct entry but don't remove the old wrong one, you might end up with both. Depending on which one the system reads first, you could still get the wrong IP.
- **Using `>` instead of `>>`:** A single `>` overwrites the entire file. If you accidentally run `echo "10.0.1.50 payments-api.internal" > /etc/hosts`, you'll wipe out all the other entries (like `127.0.0.1 localhost`) which could cause other problems.
