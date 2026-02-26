# Hints — Lab 002: DNS Resolution Failing

## Hint 1 — Confirm the symptom first
Before diving into config files, prove to yourself that DNS is actually broken. Try `ping google.com` — does it resolve? Try `dig google.com` — what does it say? Starting with the symptom tells you exactly what layer is failing.

## Hint 2 — Don't just read resolv.conf, TEST it
Looking at `/etc/resolv.conf` will show you which nameservers are configured. But don't just assume they're wrong by looking — *test* each one individually: `nslookup google.com <nameserver-ip>`. If it times out, that nameserver doesn't work. If you're not sure what a valid DNS server looks like, `8.8.8.8` is Google's free public DNS that anyone can use to test.

## Hint 3 — What if the nameserver works but lookups still fail?
There's a difference between `dig` (which queries DNS directly) and how applications like `ping` or `curl` resolve names. Linux has a configuration file that controls the *order* in which the system tries to resolve hostnames. If DNS is removed from that order, applications won't use it even if the nameserver is fine.

## Hint 4 — Internal hostnames live somewhere specific
The application needs `payments-api.internal` to resolve to `10.0.1.50`. Internal hostnames like this aren't in public DNS — they're typically mapped in a local file. Check if there's already an entry, and whether it points to the right IP.
