# Lab 068 — Solution Walkthrough: CloudFront Serving Stale Content

## TLDR (Plain English)

A support ticket lands: marketing says the pricing page is showing yesterday's prices and customers are complaining. There are **three problems** stacked on top of each other:

1. **CloudFront is pointed at the wrong "door" on the S3 bucket.** S3 has two entry points — a REST API door and a website hosting door. The config uses the wrong one, so requests fail completely.
2. **The S3 bucket is locked down.** Even after fixing the door, the website endpoint can't serve files because the bucket has no public-read policy and AWS's default Block Public Access settings would prevent any such policy from being applied.
3. **CloudFront is caching everything for 7 days by default.** Even if the first two were fixed, real updates would still take a week to appear.

**The fix:** switch CloudFront to use the S3 website endpoint (with a `custom_origin_config` block), disable Block Public Access on the bucket and add a public-read bucket policy, and drop the cache TTLs to sane values.

**The wrinkle:** these three bugs hide each other. Bug 1 is so dominant that you can't observe Bugs 2 or 3 until it's fixed. The investigation peels them off one layer at a time, and the symptom *changes* with each fix even when the surface error code looks the same.

---

## The Ticket

> **SUPPORT-4471** — Marketing reports the pricing page is showing outdated figures. They updated the S3 bucket this morning. Customers on Twitter are complaining. Please investigate and resolve.

No URL, no bucket name, no timing detail beyond "this morning." This is realistic — plenty of tickets are vague.

---

## Step 0 — Stand Up the Lab Scenario

```bash
cd ~/cloud-engineer-labs/cloud-labs/lab-068-cloudfront-caching
terraform init
terraform apply -auto-approve
bash setup.sh
```

| Command | What it does |
|---|---|
| `cd` | Move into the lab directory |
| `terraform init` | Download the AWS provider and prepare the working directory |
| `terraform apply -auto-approve` | Stand up the broken infrastructure (S3 bucket, website config, CloudFront distribution with bugs baked in) |
| `bash setup.sh` | Wait for CloudFront to deploy, seed the scenario, print the incident ticket |

**The setup script is lab scaffolding. It is not part of the diagnostic work.** In real life, an engineer inheriting an incident does not run a setup script — they inherit the broken state organically. The script simply recreates that state so you can practise on a realistic starting point.

---

## Step 1 — Read the Ticket Properly Before Touching Anything

The most undervalued step in incident response. Junior engineers leap straight to the terminal; senior engineers spend 60 seconds noticing what is and isn't there.

**What the ticket tells you:** symptom, where the change was made, vague timing, severity signal, plural affected users.

**What it doesn't:** the exact URL, which bucket, what old vs new content actually look like, whether the upload landed, scope of the problem.

In real life this is a parallel-track exercise: reply to the ticket asking for the missing details so the round-trip clock starts running, and begin investigating immediately with what you have.

---

## Step 2 — Find the Bucket

You can't list a bucket without knowing its name, and the ticket doesn't give you one. List all buckets in the account first:

```bash
aws s3 ls
```

| Part | What it does |
|---|---|
| `aws s3 ls` (no args) | Lists every bucket in the account, with creation dates |

Triage by name first (look for `marketing-`, `www-`, `website-`, `static-`), and by creation timestamp second.

**Real-world note:** in a 200-bucket production account, eyeballing won't scale. Reach for `aws s3api list-buckets --query` with a JMESPath filter, or `aws resourcegroupstaggingapi get-resources --tag-filters` if buckets are properly tagged.

---

## Step 3 — Inspect the Bucket Contents

```bash
aws s3 ls s3://$(terraform output -raw bucket_name)/ --recursive
```

| Part | What it does |
|---|---|
| `aws s3 ls s3://<bucket>/` | List the contents of the named bucket |
| `--recursive` | Walk all prefixes |

Output:

```
2026-04-12 11:15:41         36 pricing.html
```

| Column | What it tells you |
|---|---|
| `LastModified` | Object was last written at 11:15 today — matches marketing's "this morning" claim |
| `Size` | 36 bytes — small but plausible for a one-line HTML file |
| `Key` | `pricing.html` — the file marketing was talking about |

**This eliminates a whole class of failures in one command.** Marketing didn't upload to the wrong bucket, the upload didn't fail silently, the file exists and is recent. The problem is downstream of S3.

---

## Step 4 — Establish Ground Truth

Before accusing CloudFront, prove what S3 actually contains. Bypass CloudFront entirely:

```bash
aws s3 cp s3://$(terraform output -raw bucket_name)/pricing.html -
```

| Part | What it does |
|---|---|
| `aws s3 cp` | Copy an S3 object |
| `-` (as destination) | Print to stdout instead of writing a file |

Output:

```
<h1>Pricing v2 — NEW VERSION</h1>
```

**This is "ground truth."** S3 has the new content. The discipline being practised: **before accusing a downstream system (CDN, cache, replica), prove what the upstream system actually contains.**

---

## Step 5 — Reproduce the Customer's Experience

```bash
curl -s https://$(terraform output -raw distribution_domain_name)/pricing.html
```

| Part | What it does |
|---|---|
| `-s` | Silent mode — suppress the progress bar |

In the broken state, you'll get back an XML error response:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<e><Code>AccessDenied</Code>...
```

**Read what this is telling you.** The body is XML, not HTML. The format itself is a fingerprint: an XML response means you're talking to the **S3 REST API**, not a website endpoint. The ticket described "stale content," but you're seeing a *broken response*. **Trust the evidence over the narrative.**

Also check the headers:

```bash
curl -I https://$(terraform output -raw distribution_domain_name)/pricing.html
```

Look for `x-cache: Error from cloudfront`, `server: AmazonS3`, and `x-amz-cf-pop` (the edge that served you).

---

## Step 6 — Form a Hypothesis from Configuration vs Behaviour

The bucket *should* be a website (`aws_s3_bucket_website_configuration` exists in the file). CloudFront *is* getting raw S3 REST API errors. These cannot both be true unless CloudFront is bypassing the website configuration entirely.

Confirm the bucket's intended behaviour:

```bash
aws s3api get-bucket-website --bucket $(terraform output -raw bucket_name)
```

| Part | What it does |
|---|---|
| `aws s3api` | Lower-level S3 commands that map 1:1 to API calls |
| `get-bucket-website` | Returns the website hosting configuration |

Output:

```json
{ "IndexDocument": { "Suffix": "index.html" } }
```

The bucket *is* configured as a website. Hypothesis confirmed: **CloudFront is pointed at the wrong endpoint.** Time to open `main.tf`.

---

## Step 7 — Read `main.tf` With Diagnostic Intent

You're not reading top-to-bottom — you're searching for the specific block that proves the hypothesis. Navigate to the `aws_cloudfront_distribution` resource, specifically the `origin` block:

```hcl
origin {
  domain_name = aws_s3_bucket.website.bucket_regional_domain_name
  origin_id   = "S3-website"
}
```

`bucket_regional_domain_name` is the S3 *REST API* endpoint. **Bug 1 confirmed.**

While you're in the file, also note the cache TTL values:

```hcl
min_ttl     = 86400      # 1 day
default_ttl = 604800     # 7 days
max_ttl     = 31536000   # 1 year
```

**Bug 2.** Even though you can't observe staleness right now (Bug 1 prevents any successful response from being cached), these values are obviously wrong.

---

## Step 8 — Apply the First Fix

Switch the `origin` block to use the website endpoint, and add a `custom_origin_config` block:

```hcl
origin {
  domain_name = aws_s3_bucket_website_configuration.website.website_endpoint
  origin_id   = "S3-website"

  custom_origin_config {
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "http-only"
    origin_ssl_protocols   = ["TLSv1.2"]
  }
}
```

The presence of the `custom_origin_config` block is the switch that flips CloudFront from "S3 origin mode" to "custom origin mode." The website endpoint speaks plain HTTP, so `origin_protocol_policy` **must** be `http-only`.

While editing, fix the TTLs:

```hcl
min_ttl     = 0
default_ttl = 3600
max_ttl     = 86400
```

`min_ttl = 0` is the most important conceptual change — it hands cache control back to the origin via `Cache-Control` headers.

Apply and wait for CloudFront to redeploy:

```bash
terraform apply -auto-approve
aws cloudfront get-distribution \
  --id $(terraform output -raw distribution_id) \
  --query 'Distribution.Status' --output text
```

Poll until `Deployed`. Then retest:

```bash
curl -s https://$(terraform output -raw distribution_domain_name)/pricing.html
```

You'll see something different but **not yet what you wanted**:

```html
<html><head><title>403 Forbidden</title></head>...
```

**Notice what changed.** Status code is still 403. But the *format* is HTML now, not XML. **That's proof Bug 1 is fixed** — CloudFront is now talking to the website endpoint, which speaks HTML errors. Same surface symptom, different underlying behaviour.

---

## Step 9 — Bug 3: The Bucket Isn't Public

The website endpoint is now correctly receiving the request, but it can't serve the file because the bucket itself doesn't permit public read. When the website endpoint serves a file, it reads as an anonymous caller — there's no AWS authentication on these requests. No bucket policy granting `s3:GetObject` to `*` = 403.

**Enabling website hosting does not automatically make the bucket publicly readable.** Two separate concerns:

1. **Website hosting configuration** — turns on website-style behaviour
2. **Public access permissions** — controls who is allowed to read objects

Confirm:

```bash
aws s3api get-public-access-block --bucket $(terraform output -raw bucket_name)
```

All four shutters are up:

```json
{
    "BlockPublicAcls": true,
    "IgnorePublicAcls": true,
    "BlockPublicPolicy": true,
    "RestrictPublicBuckets": true
}
```

These are AWS defaults. They exist because of high-profile data leaks in 2017–2018 from accidentally-public S3 buckets. You have to disable both `BlockPublicPolicy` and `RestrictPublicBuckets`.

```bash
aws s3api get-bucket-policy --bucket $(terraform output -raw bucket_name)
```

Returns `NoSuchBucketPolicy`. No policy = no permissions = 403.

---

## Step 10 — Apply the Bug 3 Fix

Two new resources:

```hcl
resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "website" {
  bucket = aws_s3_bucket.website.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.website.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.website]
}
```

**`jsonencode()`** converts an HCL object into a JSON string. Bucket policies have to be JSON, but writing JSON inline in HCL is ugly. Use `jsonencode()` everywhere you need JSON in a string field (IAM, ECS task definitions, etc).

**The policy fields:**

| Field | Meaning |
|---|---|
| `Version` | IAM policy language version — always `2012-10-17`, vestigial |
| `Effect` | `Allow` or `Deny` |
| `Principal` | Who the statement applies to — `"*"` means anonymous public |
| `Action` | What they're allowed to do — `s3:GetObject` is read-only |
| `Resource` | What they can do it to — bucket ARN with `/*` means "all objects" |

**`depends_on`** is the explicit dependency declaration. Both the policy and the access block reference the bucket but not each other, so Terraform might apply them in parallel — and the policy would be rejected because Block Public Access was still in effect at the time. `depends_on` forces ordering. Standard idiom for the public-S3-website pattern.

Apply:

```bash
terraform apply -auto-approve
curl -s https://$(terraform output -raw distribution_domain_name)/pricing.html
```

You should finally see:

```
<h1>Pricing v2 — NEW VERSION</h1>
```

**Ticket resolved.**

---

## Step 11 — Verify Caching

Run two curls back-to-back:

```bash
curl -I https://$(terraform output -raw distribution_domain_name)/pricing.html
curl -I https://$(terraform output -raw distribution_domain_name)/pricing.html
```

First response: `x-cache: Miss from cloudfront`. Second response: `x-cache: Hit from cloudfront` and `age: 2`.

**`x-cache` flipping from `Miss` to `Hit`** proves CloudFront is caching successful responses. **The bounded `age` value** proves Bug 2 is fixed — over the next hour, `age` will grow to a maximum of `default_ttl` (3600) before triggering a refresh. If the broken TTL were still in place, `age` would climb into the hundreds of thousands of seconds before any refresh.

---

## The Final Fixed `main.tf`

A fully annotated version is at `reference/main.tf.fixed` in the lab directory. The `.fixed` extension stops Terraform from accidentally reading it.

---

## Closing the Ticket

> **Resolution — SUPPORT-4471**
>
> The pricing page is now serving the latest content. Three issues stacked together in the Terraform-managed infrastructure:
>
> 1. CloudFront origin was misconfigured — pointing at the S3 REST API endpoint instead of the website endpoint despite the bucket being set up for static website hosting. Fixed.
> 2. The bucket had no public-read policy and Block Public Access was enabled. The website endpoint cannot serve content under those conditions. Fixed.
> 3. Cache TTLs were absurdly high (default 7 days). Even with the above fixes, future content updates would have taken up to a week to appear. Reduced to 1 hour default with a 1 day ceiling.
>
> All three fixes verified end-to-end. Cache headers confirm CloudFront is serving from edge with bounded TTLs.
>
> **Beyond this ticket:**
> - The bucket has no `index.html`. Visitors hitting the site root will still get an error.
> - The website-endpoint approach is the older pattern. For better security, consider migrating to Origin Access Control as a follow-up.

---

## Lab vs Real Life

- **Cache policies over inline `forwarded_values`** — modern CloudFront uses reusable `aws_cloudfront_cache_policy` resources
- **OAC instead of public buckets** — for production, keep the bucket fully private and use Origin Access Control with the REST endpoint and HTTPS
- **Versioned filenames beat invalidation** — `app.abc123.js` URLs change whenever content changes, so no invalidation needed
- **CI/CD does invalidation automatically** — `aws s3 sync` followed by scoped `aws cloudfront create-invalidation`
- **Setup scripts don't exist in real life** — `setup.sh` is lab scaffolding; real engineers inherit broken state organically

---

## Key Takeaways

- **Bugs hide each other.** When two or more co-exist, the more severe one masks the rest. Each fix reveals what was waiting underneath. Don't get frustrated when fixing a bug "doesn't work" — read the response carefully and ask whether the symptom *changed*.
- **Trust the evidence over the ticket.** Tickets describe symptoms inaccurately. Don't bend evidence to fit the ticket's framing.
- **Establish ground truth before blaming the downstream.** Always verify what the upstream system actually contains before chasing a problem in a cache, replica, or CDN.
- **Read the response body format, not just the status code.** XML vs HTML responses tell you which subsystem produced the error. Format is a fingerprint.
- **Configuration vs behaviour mismatch is a diagnostic pattern.** When a system is misbehaving, compare what its configuration *says* it should do with what it's *actually* doing.
- **The command you want isn't always the command you can run.** There's almost always a prerequisite — recognising the gap and reaching for the smallest preparatory command is the skill.
- **`AccessDenied` doesn't always mean forbidden.** S3 returns `AccessDenied` for missing objects too.
- **Website hosting ≠ public access.** Two completely separate S3 features.
- **Block Public Access is on by default and will reject your bucket policy.** Disable it explicitly first.
- **`min_ttl = 0` is almost always correct for dynamic content.** Hands cache control back to the origin.
- **Closing the ticket well is its own skill.** Plain-language summary, fixes named, side observations surfaced.
