# Hints — WAF Rules Blocking Legitimate Traffic

## Hint 1
Look at the IP set — does it contain IPs that should be allowed or blocked? Is the IP set being used in a block rule?

## Hint 2
Rate limiting at 100 requests per 5 minutes — think about how many HTTP requests a single page load generates (HTML + CSS + JS + images + API calls).

## Hint 3
WAF rules are evaluated in priority order (lowest number first). If a block rule has priority 1, it runs before any allow rules.

## Hint 4
The geo-match rule blocks matching countries. Are you blocking countries where your users actually are?

## Hint 5
Consider separating the IP set into two: one for known malicious IPs (to block) and one for trusted office IPs (to allow).
