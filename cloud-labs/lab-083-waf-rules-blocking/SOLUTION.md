# Lab 083 — WAF Blocking Legitimate Traffic

## TLDR (Plain English)

Your app is behind AWS WAF. The security team pushed new rules over the weekend and now legitimate users — office staff, UK customers, US customers — are all getting blocked with 403 errors. The ticket lands in your inbox on Monday morning.

When you investigate, you find **four things wrong** with the WAF configuration:

1. **The office network is in a block list.** Whoever wrote the IP set mixed trusted office CIDRs (`10.0.0.0/8`, `192.168.1.0/24`) into the same list as known-malicious IPs — and that whole list is attached to a Block rule. Every office worker is blocked.
2. **The rate limit is absurdly low.** It's set to 100 requests per 5 minutes. A single modern web page load generates 20–50 requests (HTML, CSS, JS, images, API calls). Normal users trip the limit in two page loads.
3. **The rules evaluate in the wrong order.** WAF evaluates rules by priority (lowest number first). The rate-limit block rule is priority 1, so it fires before anything else can whitelist trusted traffic.
4. **The geo-block rule blocks your own customer countries.** The `geo_match_statement` lists GB, IE, and US as countries to block — but those are where your actual users live.

**The fixes:** split the IP set into trusted and malicious (with the trusted set attached to an Allow rule), raise the rate limit to 2000, reorder priorities so Allow rules run first, and either invert the geo rule with `not_statement` or change the country list to countries you don't serve.

Then `terraform apply`, then `./validate.sh`, then **`terraform destroy`** (don't forget — WAF costs money by the hour).

---

## Real-Time Investigative Walkthrough

You're on call. The ticket drops at 08:47 Monday morning: *INCIDENT-WAF-001 — support drowning in 403 complaints since weekend WAF deployment*. The security engineer who wrote the rules is on annual leave. You've never seen this WAF config before. Here's how you actually work through it.

### Step 1 — Understand what you're looking at

Before touching any code or AWS CLI command, read the ticket and look at the repo.

```bash
cd ~/cloud-engineer-labs/083-waf-rules
ls -la
cat CHALLENGE.md
```

**What this tells you:** You have `main.tf`, a `CHALLENGE.md`, and a `validate.sh`. The scenario says users are getting 403s after a weekend WAF push. Health checks pass — so it's not a backend problem. The backend is fine. Something at the edge (the WAF itself) is rejecting real traffic.

**Resist the urge to open `main.tf` first.** If this were real, you wouldn't have a nicely-commented Terraform file waiting for you — you'd have live AWS infrastructure and a mess to diagnose. The point of this lab is to practise diagnosing from AWS itself.

### Step 2 — Deploy the current (broken) state so you can investigate it live

```bash
terraform init
terraform apply
```

Type `yes` when prompted. This takes ~30 seconds and spins up a real Web ACL and IP set in your AWS account in `eu-west-2`.

**Why apply a config we know is broken?** Because in real life, the broken config is already running in production. You're not diagnosing a text file — you're diagnosing *deployed infrastructure*. The AWS console and CLI are your primary tools, not `main.tf`.

After apply completes, Terraform outputs the Web ACL ARN, ID, and name. Make a note of the ID — you'll need it repeatedly.

### Step 3 — Choose the right tool for the job

Before going further, it's worth pausing to think about **which tools to reach for**. There's a widespread myth in DevOps that "real engineers never use the AWS Console." That's an over-simplification of a real principle. The actual rule is:

| Phase of work | Right tool | Why |
|---|---|---|
| Creating/modifying/destroying resources | **Terraform** | Reproducible, reviewed, version-controlled. Click-ops creates drift and is untraceable. |
| Scripted queries, automation, runbooks | **AWS CLI** | Scriptable, pipe-able, exact. Good for CI/CD and reproducible debugging. |
| Exploratory investigation, time-series data, reading logs/metrics | **AWS Console** | Visual, fast, sortable tables and charts. Best for *understanding* an incident. |

The rule "never touch the console" really means **"never use the console to make changes."** Reading from the console is just using the right tool for the job — especially for time-series data like WAF sampled requests, where a visual UI beats constructing ISO-8601 timestamps in bash.

For this incident, the realistic flow is **Console → CLI → Terraform**:

1. **Console first** — understand *what* is being blocked. Visual, fast.
2. **CLI second** — once you've identified the suspect rules, dump their exact config so you can reason about them and paste evidence into a ticket.
3. **Terraform last** — make the fix in code, apply, validate.

Let's follow that path.

### Step 4 — Open the WAF Console and look at sampled requests

This is what you'd actually do first in a real incident. Navigate in the AWS Console to:

```
WAF & Shield → Web ACLs → (select region: eu-west-2) → app-waf-acl → Sampled requests tab
```

In a real production incident you'd see a table of the most recent requests WAF has seen, which rule matched, and what action was taken (Allow / Block / Count). You can filter by time window and by rule. This is the fastest way to answer questions like *"which rule is blocking the most traffic?"* and *"what IPs are being blocked?"*

**On this freshly-deployed lab WAF, the Sampled Requests tab will be empty** because no real traffic has hit the WAF yet. That's a lab limitation — in reality the ACL has been live for the whole weekend and would have plenty of blocked requests to show.

Since we can't rely on sampled requests for this lab, switch to the next most useful tab in the console:

```
WAF & Shield → Web ACLs → app-waf-acl → Rules tab
```

This shows all rules in the ACL in their evaluation order, with their actions (Allow / Block / Count) and priorities. You can click any rule to see its full statement.

**This is where you'd start forming hypotheses.** Even without seeing live traffic, an experienced engineer looks at this page and asks:

- *Are there any Allow rules?* (If not — trusted IPs have no protection.)
- *What priorities do the Block rules have?* (Low numbers = evaluated first = can block users before anything allows them.)
- *Do the Block rules' statements look sensible?* (Rate limits that are too low? Geo-blocks on your own markets? IP sets with suspicious contents?)

### Step 5 — Confirm the diagnosis with the CLI

Once you've spotted suspicious-looking rules in the console, pull the exact configuration with the CLI. This gives you paste-able evidence for a ticket and is faster than clicking into each rule in the UI.

```bash
# Get the Web ACL ID
ACL_ID=$(aws wafv2 list-web-acls --scope REGIONAL --region eu-west-2 \
  --query "WebACLs[?Name=='app-waf-acl'].Id" --output text)

echo "Web ACL ID: $ACL_ID"
```

**Command breakdown — `aws wafv2 list-web-acls`:**

| Component | What it does |
|---|---|
| `aws wafv2` | AWS CLI namespace for WAF v2 (the current generation of AWS WAF) |
| `list-web-acls` | Returns all Web ACLs in the scope |
| `--scope REGIONAL` | WAF has two scopes: `REGIONAL` (for ALB, API Gateway, App Runner) and `CLOUDFRONT` (for CloudFront distributions, which must be queried from us-east-1). We're REGIONAL here. |
| `--region eu-west-2` | Query the London region |
| `--query "WebACLs[?Name=='app-waf-acl'].Id"` | JMESPath filter: from the WebACLs array, find the one named `app-waf-acl`, return its Id field |
| `--output text` | Return as plain text (easier to capture into a variable) than the default JSON |

Now dump the full Web ACL config:

```bash
aws wafv2 get-web-acl \
  --name app-waf-acl \
  --scope REGIONAL \
  --id "$ACL_ID" \
  --region eu-west-2
```

**Command breakdown — `aws wafv2 get-web-acl`:**

| Component | What it does |
|---|---|
| `get-web-acl` | Returns the full definition of one Web ACL — all rules, actions, statements, priorities |
| `--name app-waf-acl` | The Web ACL's name |
| `--scope REGIONAL` | Same scope logic as before |
| `--id "$ACL_ID"` | The UUID of the Web ACL — required alongside the name because names aren't globally unique |

You get back a big JSON blob. Scroll through the `Rules` array. Four things should catch your eye as an experienced engineer, and this is the investigative sequence you'd actually follow.

#### Observation 1 — The rate-limit rule is priority 1

You see this at the top of the `Rules` array:

```json
{
  "Name": "rate-limit",
  "Priority": 1,
  "Action": { "Block": {} },
  "Statement": {
    "RateBasedStatement": {
      "Limit": 100,
      "AggregateKeyType": "IP"
    }
  }
}
```

**How would you know this is wrong?** Two red flags:

- **`Limit: 100` per 5 minutes is aggressive.** Ask yourself: *is 100 requests in 5 minutes a realistic threshold for legitimate traffic?* A modern web page loads 20–50 assets. A user clicking around for a couple of minutes easily generates several hundred requests. 100 is the kind of number you'd set for an API endpoint you expect to be called rarely — not for a web application.
- **`Priority: 1` means this runs first.** In WAF, lower priority numbers are evaluated earlier. If a request matches a Block rule, WAF stops evaluating and blocks it. So putting an aggressive Block rule at priority 1 guarantees that **no later Allow rule can rescue legitimate traffic**.

**Where do you look to confirm rule priority semantics?** AWS WAF docs — or just reason from first principles: if block rules run first, there's no way to whitelist anything. So Allow rules must run first. That means Allow rules should have the *lowest* priority numbers.

#### Observation 2 — The IP blocklist contains private CIDR ranges

Next rule in the ACL:

```json
{
  "Name": "ip-blocklist",
  "Priority": 2,
  "Action": { "Block": {} },
  "Statement": {
    "IPSetReferenceStatement": {
      "ARN": "arn:aws:wafv2:eu-west-2:...:ipset/office-ip-set/..."
    }
  }
}
```

The rule references an IP set. Pull the contents of that set:

```bash
IPSET_ID=$(aws wafv2 list-ip-sets --scope REGIONAL --region eu-west-2 \
  --query "IPSets[?Name=='office-ip-set'].Id" --output text)

aws wafv2 get-ip-set \
  --name office-ip-set \
  --scope REGIONAL \
  --id "$IPSET_ID" \
  --region eu-west-2
```

**Command breakdown — `aws wafv2 get-ip-set`:**

| Component | What it does |
|---|---|
| `get-ip-set` | Returns the full definition of one IP set — including all CIDR addresses |
| `--name office-ip-set` | The IP set's name |
| `--scope REGIONAL` | Same scope logic |
| `--id "$IPSET_ID"` | The UUID of the IP set |

The output shows:

```json
{
  "IPSet": {
    "Addresses": [
      "10.0.0.0/8",
      "192.168.1.0/24",
      "203.0.113.50/32",
      "198.51.100.100/32"
    ]
  }
}
```

**Stop and think.** The IP set is called **office-ip-set** and it's attached to a **Block** rule.

- `10.0.0.0/8` is RFC 1918 private address space — that's your internal network
- `192.168.1.0/24` is also RFC 1918 — typical home/office network
- `203.0.113.50/32` and `198.51.100.100/32` are TEST-NET-3 and TEST-NET-2 (documentation ranges, standing in here for malicious public IPs)

**The trusted office CIDRs are in the same list as the malicious IPs, and the whole list is being blocked.** This is the first clear bug.

**How would you know `10.0.0.0/8` and `192.168.1.0/24` are office ranges?** The name of the IP set literally says "office-ip-set", and RFC 1918 ranges are instantly recognisable to any network engineer. The inconsistency between the name ("office") and the action ("Block") is the tell.

#### Observation 3 — The geo rule blocks your own customers

Third rule:

```json
{
  "Name": "geo-block",
  "Priority": 3,
  "Action": { "Block": {} },
  "Statement": {
    "GeoMatchStatement": {
      "CountryCodes": ["GB", "IE", "US"]
    }
  }
}
```

**This rule blocks traffic from Great Britain, Ireland, and the United States.**

**How would you know these are wrong countries to block?** Two sources:

- The ticket says "UK customers" and "US customers" are getting blocked. That alone tells you GB and US are legitimate markets.
- If you didn't have the ticket, you'd confirm with the business — *which countries do we actually serve?* — before changing a geo rule in either direction.

Geo-blocking has two common patterns. The one in use here ("block these N countries, allow everything else") is dangerous because it fails open — any country you didn't think to add gets through. The safer inverse pattern ("block everything except these N countries") fails closed. For this business (UK + Ireland + US customers), inverting to an allow-list is the better fix.

#### Observation 4 — Putting the priority bug together

Now step back and look at all three rules' priorities:

| Priority | Rule | Action | Problem |
|---|---|---|---|
| 1 | rate-limit | Block | Fires first. Blocks users before anything else can whitelist them. |
| 2 | ip-blocklist | Block | Includes office IPs by mistake. |
| 3 | geo-block | Block | Blocks customer countries. |

**There are no Allow rules.** This means even if we fix the geo bug and the rate limit, trusted office traffic has nothing protecting it — it can still be caught by future Block rules. The design needs an explicit **trusted-ip Allow rule at priority 1**, so office traffic is whitelisted before any Block rule gets a chance.

### Step 6 — Translate your diagnosis into a fix

Four bugs, four fixes. Open `main.tf` now — for the first time.

```bash
vi main.tf
```

#### Fix 1 — Split the IP sets

The current single IP set mixes trusted and malicious. Split it:

```hcl
resource "aws_wafv2_ip_set" "malicious_ips" {
  name               = "malicious-ip-set"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses = [
    "203.0.113.50/32",
    "198.51.100.100/32",
  ]
}

resource "aws_wafv2_ip_set" "trusted_ips" {
  name               = "trusted-ip-set"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses = [
    "10.0.0.0/8",
    "192.168.1.0/24",
  ]
}
```

#### Fix 2 — Add an Allow rule at priority 1 for trusted IPs

```hcl
rule {
  name     = "allow-trusted-ips"
  priority = 1
  action {
    allow {}
  }
  statement {
    ip_set_reference_statement {
      arn = aws_wafv2_ip_set.trusted_ips.arn
    }
  }
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "allow-trusted-ips"
    sampled_requests_enabled   = true
  }
}
```

#### Fix 3 — Reorder block rules and raise the rate limit

```hcl
rule {
  name     = "ip-blocklist"
  priority = 2
  action {
    block {}
  }
  statement {
    ip_set_reference_statement {
      arn = aws_wafv2_ip_set.malicious_ips.arn
    }
  }
  # visibility_config unchanged
}

rule {
  name     = "rate-limit"
  priority = 3
  action {
    block {}
  }
  statement {
    rate_based_statement {
      limit              = 2000
      aggregate_key_type = "IP"
    }
  }
  # visibility_config unchanged
}
```

**Why 2000?** AWS WAF rate-based rules count requests per 5-minute rolling window. 2000 / 300 seconds ≈ 6.7 requests per second per IP. That accommodates normal browsing (even heavy page loads) while still catching scrapers and brute-force attempts. Tune up or down based on your actual traffic — this is a sensible starting point, not a universal answer.

#### Fix 4 — Invert the geo rule

Change from "block these three countries" to "block everything except these three countries":

```hcl
rule {
  name     = "geo-block"
  priority = 4
  action {
    block {}
  }
  statement {
    not_statement {
      statement {
        geo_match_statement {
          country_codes = ["GB", "IE", "US"]
        }
      }
    }
  }
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "geo-block"
    sampled_requests_enabled   = true
  }
}
```

**Command breakdown — the `not_statement` pattern:**

| Component | What it does |
|---|---|
| `statement { not_statement { ... } }` | Inverts whatever the inner statement matches |
| `statement { geo_match_statement { country_codes = [...] } }` | Inner match: country is in the given list |
| Combined | "Match if country is NOT in GB/IE/US" — i.e. block everyone except those three countries |

This is the safe-by-default pattern. Any new country that becomes a customer will *also* be blocked until you add it — which forces the business decision to be explicit.

### Step 7 — Apply and verify

```bash
terraform plan
```

Review the plan carefully:
- One new `trusted-ips` IP set created
- `office-ip-set` renamed to `malicious-ip-set` with only the malicious CIDRs
- One new Allow rule added at priority 1
- Existing rules renumbered
- Rate limit changed from 100 to 2000
- Geo rule wrapped in `not_statement`

If that looks right:

```bash
terraform apply
```

Now run the validation:

```bash
./validate.sh
```

You should see all checks pass. If any fail, read the failure message — the script tells you exactly which property of the live AWS resource doesn't match expectation.

### Step 8 — Clean up (don't skip this)

```bash
terraform destroy
```

Type `yes`. This removes the Web ACL, IP sets, and all CloudWatch metric definitions. **WAF charges by the hour** — roughly $5/month for the Web ACL and $1/month per rule. If you leave it running by accident it's a slow bleed on your bill.

---

## Useful Commands Reference

The full set of WAF inspection commands used in this lab:

```bash
# List all Web ACLs in a region
aws wafv2 list-web-acls --scope REGIONAL --region eu-west-2

# Get full Web ACL config (rules, priorities, actions)
aws wafv2 get-web-acl --name <NAME> --scope REGIONAL --id <ID> --region eu-west-2

# List all IP sets
aws wafv2 list-ip-sets --scope REGIONAL --region eu-west-2

# Get IP set contents
aws wafv2 get-ip-set --name <NAME> --scope REGIONAL --id <ID> --region eu-west-2

# Get sampled blocked requests (for live debugging)
aws wafv2 get-sampled-requests \
  --web-acl-arn <ARN> \
  --rule-metric-name <METRIC_NAME> \
  --scope REGIONAL \
  --time-window "StartTime=<ISO8601>,EndTime=<ISO8601>" \
  --max-items 100
```

---

## Key Concepts

- **Rule priority determines evaluation order.** Lower numbers evaluate first. WAF stops at the first matching rule — so put Allow rules before Block rules if you want a whitelist to override a blocklist. The standard structure is: **allow trusted → block known bad → rate limit → geo → default action**.
- **Allow-lists and block-lists are separate concepts.** Never mix them in one IP set. Give them different names (`trusted-ip-set`, `malicious-ip-set`) and different actions (Allow, Block). Mixing them is how this lab's bug was born in the first place.
- **Rate limits must be grounded in real traffic patterns.** 100 req/5min sounds reasonable until you remember that a single modern page load is 30+ requests. Measure your actual traffic with CloudWatch before you pick a number. If you don't have data, deploy in COUNT mode first and observe.
- **Geo-rules can fail open or fail closed.** Blocking specific countries fails open — new countries get through. Wrapping `geo_match_statement` in `not_statement` fails closed — new countries are blocked until explicitly allowed. Prefer fail-closed for security rules.
- **WAF has observability built in.** `cloudwatch_metrics_enabled` and `sampled_requests_enabled` are on by default in this lab — and should *always* be on. Without them you can't see what's being blocked and you can't diagnose incidents like this one.
- **Terraform's dependency graph has edge cases.** When resources reference each other through ARN strings buried inside nested blocks (as WAF rules do), Terraform's scheduler can pick parallel orderings that AWS refuses. Know the `-target` recovery pattern and understand why it's a workaround, not a routine tool.

---

## Lab vs Real Life

| This lab | Real life |
|---|---|
| Four bugs are all in one file you can read | Bugs are spread across Terraform modules, sometimes across repos, with stale PRs |
| You deploy and destroy in five minutes | The broken config has been running in prod since the weekend, cost is mounting, customers are angry |
| No real traffic hitting the WAF, so `get-sampled-requests` is empty | Sampled requests is the first and most powerful debugging tool — you see actual blocked IPs, timestamps, URIs |
| Health checks are specified as healthy in the ticket | In reality you'd be cross-referencing ALB metrics, target health, backend logs, and WAF metrics simultaneously |
| You can destroy when done | Prod WAFs live for years and accumulate rules from everyone who's ever touched them. Rule sprawl is the bigger long-term problem than any single bug. |
| Fix-and-apply is the workflow | Real WAF changes get tested in COUNT mode for days before switching to BLOCK |

---

## Real-World Gotchas Encountered During This Lab

This section documents issues that arose during a live run of this lab. They're not bugs in the config — they're real-world AWS and Terraform behaviours that every engineer working with WAF will eventually hit. Understanding them matters more than memorising the commands.

### Gotcha 1 — `WAFAssociatedItemException` on IP set delete

During the first `terraform apply` of the fix, Terraform tried to destroy the old `office_ips` IP set (which is no longer in the new config) in parallel with creating the two new IP sets and updating the Web ACL. The destroy hung for ~5 minutes before failing with:

```
Error: deleting WAFv2 IPSet: WAFAssociatedItemException: AWS WAF couldn't
perform the operation because your resource is being used by another resource
or it's associated with another resource.
```

**What happened:** AWS WAF refuses to delete an IP set while any Web ACL still references it. Even though the *new* Terraform config has the Web ACL pointing at `malicious_ips` instead, at the moment of the delete attempt the Web ACL in AWS hadn't been updated yet. AWS saw the old `ip-blocklist` rule still pointing at `office_ips` and blocked the deletion.

**Why Terraform got the ordering wrong:** Terraform's dependency graph builds from explicit references in the `.tf` config. In the *new* config, nothing references `office_ips`, so Terraform decided it was safe to destroy in parallel with other operations. But the dependency was implicit — it existed in the *old state* (the running Web ACL), not in the *new config*. Terraform's scheduler therefore picked an execution order that AWS refused.

**The recovery pattern:** Use `-target` to force the Web ACL update to complete first, then run a plain apply to let Terraform clean up the orphan:

```bash
# Step 1 — update only the Web ACL (clears the old reference)
terraform apply -target=aws_wafv2_web_acl.main

# Step 2 — verify in AWS that the new rules are live
aws wafv2 get-web-acl --name app-waf-acl --scope REGIONAL \
  --id <ACL_ID> --region eu-west-2 \
  --query 'WebACL.Rules[].[Name,Priority]' --output table

# Step 3 — run plain apply to destroy the now-unreferenced IP set
terraform apply
```

### Gotcha 2 — `-target` is a workaround, not a habit

`-target` restricts a Terraform operation to a specific resource. It's useful for exactly this kind of recovery, but **don't reach for it routinely**. HashiCorp explicitly designates it for exceptional circumstances because it breaks Terraform's normal guarantee that your config and your infrastructure stay in sync after an apply. Used casually, it leads to state drift — resources in your config that never get created, or updates that never land, because someone kept using `-target` to do one thing at a time.

**When to use it:**
- Recovering from a failed apply where one resource is blocking others
- Forcing a specific update order when the dependency graph is getting it wrong
- Debugging — applying one resource at a time to understand where an error originates

**When not to use it:**
- Routine workflows
- Because a plan shows more changes than you expected (investigate those changes instead)
- Skipping changes you don't want to apply (edit the config instead)

### Gotcha 3 — LockTokens and optimistic concurrency

AWS WAF uses **LockTokens** on mutable resources (IP sets, Web ACLs, rule groups). Every read returns a `LockToken`; every write or delete requires you to send the current `LockToken` back. If someone else has modified the resource in the meantime, your token is stale and AWS rejects the call.

This is called **optimistic concurrency control** — instead of locking the resource while you work on it (which would serialise all changes and slow everything down), AWS lets multiple callers read freely and only checks for conflicts at write time.

Terraform handles LockTokens automatically — you won't see them in `.tf` files. But if you ever work with WAF via AWS CLI or SDK directly, you need to fetch the current token before any mutation:

```bash
# Get the current LockToken
LOCK_TOKEN=$(aws wafv2 get-ip-set --name my-set --scope REGIONAL \
  --id <id> --region eu-west-2 --query 'LockToken' --output text)

# Use it in the subsequent delete/update
aws wafv2 delete-ip-set --name my-set --scope REGIONAL \
  --id <id> --lock-token "$LOCK_TOKEN" --region eu-west-2
```

### Gotcha 4 — Destroy ordering is easier than update-then-destroy

At the end of the lab, `terraform destroy` cleanly tore down everything in the correct order (Web ACL first, then both IP sets — each taking under a second). This is the same dependency relationship that caused the apply to fail earlier. So why did destroy work but apply fail?

**Destroy is easier because the dependency is unambiguous.** When destroying everything, Terraform knows the Web ACL must die before the IP sets — they're all going away and the Web ACL is the parent. No ambiguity, no parallelism to get wrong.

**Apply is harder** when you're simultaneously updating a resource (the Web ACL) and destroying a resource it used to reference (the old IP set). Terraform has to infer from config that "update the parent before destroying the orphan child" — and for WAF's rule-block references via ARN strings, it sometimes doesn't.

**The takeaway:** Terraform's dependency graph is excellent but not infallible. When resources reference each other through ARN strings nested inside block definitions (rather than through top-level attribute references), edge cases appear. Knowing how to recognise and recover from these is part of operating infrastructure at scale.

---



- **Testing WAF rules in BLOCK mode in production.** Always deploy new rules with `action { count {} }` first, observe CloudWatch metrics for a day or two, then switch to Block once you're confident the rule matches only what you expect.
- **Setting rate limits by guessing.** Rate limits should come from measured traffic, not intuition. Start permissive, tighten based on observation.
- **Forgetting about CloudFront.** If your traffic comes through CloudFront, all IPs will appear as CloudFront IPs unless you configure `forwarded_ip_config` on the rule. Your rate-limit and IP rules become useless otherwise.
- **Ignoring API endpoints.** APIs legitimately make many more requests than browser traffic. Often the right answer is a separate rate-limit rule with a higher threshold scoped to the API path.
- **Forgetting to destroy.** WAF costs add up. Always run `terraform destroy` at the end of testing.

---

## Cleanup & Reset

To re-run this lab from scratch:

```bash
# Destroy any current infrastructure
terraform destroy

# Reset main.tf to the broken starting state
git checkout main.tf

# Clear Terraform state
rm -rf .terraform terraform.tfstate*

# Start over
terraform init
terraform apply
```
