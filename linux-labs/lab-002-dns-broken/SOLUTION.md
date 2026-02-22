# Solution Walkthrough — DNS Resolution Failing

## The Problem

DNS (Domain Name System) is the system that translates human-readable names like `google.com` into IP addresses like `142.250.80.46`. On this server, DNS is completely broken — the machine can't resolve any hostnames. There are **three separate issues**:

1. **`/etc/resolv.conf` has invalid nameservers** — the file that tells the system which DNS servers to use has been filled with bogus IP addresses (`192.168.999.1` isn't even a valid IP — octets can't exceed 255, and `10.255.255.254` is unreachable).
2. **`/etc/hosts` has a wrong entry for an internal service** — the `payments-api.internal` hostname is mapped to the wrong IP address (`10.0.99.99` instead of the correct `10.0.1.50`).
3. **`/etc/nsswitch.conf` was modified to skip DNS entirely** — this file controls the order in which Linux looks up hostnames. Someone changed it so the system only checks `/etc/hosts` and never queries DNS servers, meaning any hostname not in `/etc/hosts` will fail to resolve.

## Thought Process

When DNS isn't working, an experienced engineer checks things in order of how Linux resolves names:

1. **Can we reach any DNS server at all?** Check `/etc/resolv.conf` to see what nameservers are configured. Are they valid IPs? Are they reachable?
2. **Is the system even trying to use DNS?** Check `/etc/nsswitch.conf` — the `hosts:` line controls whether the system queries DNS at all. If it only says `files`, the system will only ever check `/etc/hosts`.
3. **Are there any static overrides?** Check `/etc/hosts` for entries that might be overriding or conflicting with expected resolutions.

The key insight is that Linux name resolution is a multi-layer system: `nsswitch.conf` decides the strategy, `/etc/hosts` provides local overrides, and `/etc/resolv.conf` points to the DNS servers. All three layers need to be correct.

## Step-by-Step Solution

### Step 1: Check the current DNS configuration

```bash
cat /etc/resolv.conf
```

**What this does:** Shows you which DNS servers the system is configured to use. You'll see the invalid entries — `192.168.999.1` (not a valid IP address at all) and `10.255.255.254` (an unreachable address).

### Step 2: Fix resolv.conf with the correct nameserver

```bash
cat > /etc/resolv.conf << 'EOF'
nameserver 127.0.0.11
search localdomain
EOF
```

**What this does:** Replaces the broken DNS configuration with a working one. In a Docker container, `127.0.0.11` is Docker's built-in DNS server that handles name resolution. The `search` line sets the default domain suffix for short hostnames. We use `cat >` with a heredoc to write the entire file contents at once.

### Step 3: Check nsswitch.conf

```bash
grep '^hosts:' /etc/nsswitch.conf
```

**What this does:** Shows the current name resolution order. You'll see `hosts: files` which means the system only checks `/etc/hosts` and never queries DNS servers. This is why even with a valid nameserver in `resolv.conf`, external hostnames still wouldn't resolve.

### Step 4: Fix nsswitch.conf to include DNS lookups

```bash
sed -i 's/^hosts:.*/hosts:          files dns/' /etc/nsswitch.conf
```

**What this does:** Changes the `hosts:` line so the system first checks `/etc/hosts` (`files`) and then queries DNS servers (`dns`). This is the standard configuration on most Linux systems. The `sed -i` command edits the file in place — the `s/old/new/` syntax means "substitute."

### Step 5: Check /etc/hosts for incorrect entries

```bash
grep payments-api /etc/hosts
```

**What this does:** Looks for any entries related to `payments-api.internal`. You'll see it's mapped to `10.0.99.99`, which is the wrong IP address.

### Step 6: Fix the /etc/hosts entry

```bash
sed -i '/payments-api.internal/d' /etc/hosts
echo "10.0.1.50  payments-api.internal" >> /etc/hosts
```

**What this does:** First, we delete any existing lines containing `payments-api.internal` (the `-i` flag edits in place, the `/pattern/d` syntax means "delete lines matching this pattern"). Then we add the correct entry mapping `payments-api.internal` to `10.0.1.50`. The `>>` appends to the file rather than overwriting it.

### Step 7: Verify DNS resolution is working

```bash
dig +short google.com
```

**What this does:** `dig` is a DNS lookup tool. The `+short` flag gives you a concise answer — just the IP address(es). If this returns one or more IP addresses, external DNS is working again.

### Step 8: Verify the internal hostname resolves correctly

```bash
getent hosts payments-api.internal
```

**What this does:** `getent` queries the system's name resolution (using the full nsswitch.conf chain, including `/etc/hosts`). This verifies that `payments-api.internal` resolves to `10.0.1.50`.

## Docker Lab vs Real Life

- **DNS server address:** In this lab, Docker's internal DNS is at `127.0.0.11`. On a real server, you'd use your network's DNS servers — on AWS EC2, the VPC DNS resolver is at the VPC CIDR base + 2 (e.g., `10.0.0.2`). On a corporate network, you'd use your company's DNS servers.
- **Editing resolv.conf:** In production, `/etc/resolv.conf` is often managed by `systemd-resolved`, `NetworkManager`, or DHCP. Editing it directly may get overwritten. On modern Ubuntu, you'd configure DNS through `netplan` or `systemd-resolved` config files instead.
- **Internal hostnames:** In production, internal services like `payments-api.internal` would typically be managed through private DNS zones (like AWS Route 53 private hosted zones) rather than `/etc/hosts` entries.

## Key Concepts Learned

- **Linux name resolution is a multi-layer system** — `nsswitch.conf` controls the strategy, `/etc/hosts` provides local mappings, and `/etc/resolv.conf` points to DNS servers
- **`/etc/nsswitch.conf` is the gatekeeper** — if `dns` isn't listed in the `hosts:` line, the system will never query DNS servers, no matter what's in `resolv.conf`
- **`/etc/hosts` takes priority over DNS** — because `files` comes before `dns` in nsswitch.conf, a wrong entry in `/etc/hosts` will override the correct DNS answer
- **IP address validation matters** — `192.168.999.1` isn't valid because each octet must be 0-255. Spotting this instantly tells you the config is broken.
- **`dig`, `nslookup`, and `getent` are your DNS debugging tools** — `dig` queries DNS servers directly, while `getent` uses the full system resolution chain

## Common Mistakes

- **Only fixing resolv.conf** — this is the most obvious issue, but fixing it alone won't help if nsswitch.conf is telling the system to skip DNS entirely
- **Not removing the wrong /etc/hosts entry** — if you fix DNS but leave the bad `10.0.99.99` entry in `/etc/hosts`, that wrong answer will take priority because `files` comes before `dns` in nsswitch.conf
- **Using `8.8.8.8` as the nameserver in Docker** — Google's public DNS works on regular servers but may not work inside Docker containers that rely on Docker's internal DNS (`127.0.0.11`) for container-to-container name resolution
- **Forgetting to test both internal and external resolution** — you need to verify that both `google.com` (external DNS) and `payments-api.internal` (local hosts file) work correctly
