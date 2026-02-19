# Hints — Lab 007: Firewall Blocking

## Hint 1 — Confirm the apps are running
Use `ss -tlnp` or `netstat -tlnp` to verify processes are listening on 8080 and 8081. If they are, the issue is the firewall, not the app.

## Hint 2 — Read the current rules
`iptables -L INPUT -n --line-numbers` shows all current rules. Look for what's allowed and what's missing. The default policy at the top tells you what happens to unmatched traffic.

## Hint 3 — Add the missing rules
You need to add ACCEPT rules for ports 8080 and 8081 on the loopback interface. Use `iptables -A INPUT -i lo -p tcp --dport 8080 -j ACCEPT` (and the same for 8081). Order matters — add them before any DROP rules.
