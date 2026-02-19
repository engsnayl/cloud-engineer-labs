# Hints — Lab 002: DNS Resolution Failing

## Hint 1 — Start with the obvious
Check `/etc/resolv.conf` — are the nameservers actually valid IP addresses? In Docker containers, the DNS server is typically the Docker bridge gateway (often `127.0.0.11`). On EC2, it's usually the VPC DNS at `x.x.x.2`.

## Hint 2 — DNS isn't the only way to resolve hostnames
Linux checks `/etc/nsswitch.conf` to decide HOW to resolve names. The `hosts:` line controls the order — `files` means /etc/hosts, `dns` means nameservers. What if one of those is missing?

## Hint 3 — Check /etc/hosts carefully
There might already be an entry for the internal service — but is it the RIGHT IP address?
