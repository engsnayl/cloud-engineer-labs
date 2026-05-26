# Phase 2 Pilot — 10 MCQs for quality-bar review

**Purpose:** Per Appendix B Phase 2, this is the first authoring batch. The
quality bar is **Appendix A** in the brief. Sign-off (or redlines) on these
10 determines whether Phase 3 proceeds as-is or recalibrates.

## What's in this batch

10 MCQs across 4 domains, 3 banks, mixed priorities:

| Domain | Count | Sources |
|---|---|---|
| AWS | 3 | aws-002 (mcq-2), aws-003 (mcq-1), aws-026 (mcq-1) |
| Kubernetes | 3 | k8s-001 (mcq-1), k8s-005 (mcq-2), k8s-010 (mcq-1) |
| Terraform | 2 | tf-002 (mcq-2), tf-011 (mcq-1) |
| CI/CD | 2 | cicd-020 (mcq-1), cicd-030 (mcq-1) |

Priority mix: **8 critical, 1 high, 1 medium**. Difficulty mix: **4 easy, 6 medium**.

Bank coverage (where each MCQ would land in the final 3-bank split):
B1 = 6, B2 = 2, B3 = 2.

The two Appendix A samples whose `mcq-1` was fully written out by you
(aws-002, k8s-005, tf-002) — I authored their **mcq-2** here instead, so
this batch covers ten new MCQs rather than re-typing your samples.

## Self-review summary (Section 4.7 applied)

All ten pass programmatic checks via `scripts/validate_mcqs.py`:

- 0 banned phrases ("all of the above" / "none of the above")
- 0 absolutes in distractors ("always" / "never" / "100%")
- All 10 explanations 89-112 words (cap 120)
- Every explanation references all three distractors
- "Correct is the longest option" pattern: 1/10 (a 111-char tie with two distractors), down from 8/10 in the first draft after rebalancing

The remaining judgment calls — does each MCQ teach the right concept, are
the distractors plausible to a Solutions Architect Associate candidate,
do explanations close the loop on why each distractor fails — are below
per MCQ.

## File layout

- `pilot.json` — the 10 MCQs in the brief Section 5.2 schema (production format, ready to migrate into `interview-N.json` once approved)
- `PILOT-REVIEW.md` — this document
- `../scripts/validate_mcqs.py` — the schema + style validator

The `bank` field on each MCQ is informational for this pilot only (it's
the destination bank from the Phase 1 allocation) — it won't appear in
the production bank files since file location implies bank.

## MCQ walkthrough

For each MCQ: angle, the distractor patterns used (per brief Section 4.2),
and the "what's the trap" thought.

---

### 1. `aws-002-mcq-2` — Networking (high, easy, B2)

**Angle:** NAT Gateway vs IGW placement and direction — the public/private subnet question framed as a real workload need.

**Distractor patterns:**
- D1 (IGW in private subnet): *half-remembered* — knows internet needs IGW, doesn't know placement makes it public.
- D2 (NAT in private subnet): *half-remembered* with subtle wrong placement; NAT GW must sit in a public subnet.
- D3 (VPC Gateway Endpoint for EC2): *real concept, wrong context* — endpoints reach specific AWS services, not the public internet.

**Trap:** Candidates who pattern-match "need internet → IGW route" will pick D1 without realising it makes the subnet public.

---

### 2. `aws-003-mcq-1` — Networking (critical, easy, B1)

**Angle:** Stateful SG vs stateless NACL — the return-traffic behaviour that breaks asymmetric NACL configs in production.

**Distractor patterns:**
- D1 (SG state "inherits" into NACL): *symmetric-but-wrong* — neat parallel that makes SG and NACL behave the same way.
- D2 (NACL drops the inbound SYN): *half-remembered* — inverts which direction fails; inbound is fine, outbound is the problem.
- D3 (AWS implicit ephemeral-port allow): *what-would-happen-if-NACL-were-stateful* — invents a behaviour that doesn't exist.

**Trap:** A candidate who memorised "SG stateful, NACL stateless" but never applied it under outbound-blocking conditions will fail.

---

### 3. `aws-026-mcq-1` — IAM (critical, easy, B1)

**Angle:** IAM role vs IAM user for workload identity — the EC2-to-S3 case.

**Distractor patterns:**
- D1 (IAM user with static keys in ~/.aws/credentials): *half-remembered* — "users grant permissions" is true, but they're the wrong shape for workloads.
- D2 (access key in user data): *what-would-happen-without-a-role* — worse variant of D1; exposes the key via describe-instance.
- D3 (Security Group rule to S3): *adjacent technology confusion* — conflates network reachability with IAM authorization.

**Trap:** Junior candidates often reach for IAM users because they've seen `aws configure` set them up locally.

---

### 4. `k8s-001-mcq-1` — Workloads (critical, easy, B1)

**Angle:** Controller hierarchy — who actually orchestrates a rolling update.

**Distractor patterns:**
- D1 (new ReplicaSet "inherits" old pods): *half-remembered* — confuses ownership; each RS only manages its own pods.
- D2 (pods self-coordinate): *symmetric-but-wrong* — invents a flat peer-to-peer model.
- D3 (kube-scheduler manages RS transitions): *adjacent technology confusion* — scheduler places pods on nodes; it doesn't run rollouts.

**Trap:** A candidate who's only ever read `kubectl describe deploy` output won't have thought about which controller drives the diff.

---

### 5. `k8s-005-mcq-2` — Workloads (critical, medium, B3)

**Angle:** QoS class assignment rules — when matching one resource isn't enough.

**Distractor patterns:**
- D1 (Guaranteed because memory matches): *half-remembered* — close to the rule but missing "all resources must match".
- D2 (Guaranteed because all resources are set): *half-remembered* — conflates "set" with "equal".
- D3 (BestEffort): *real concept, wrong context* — BestEffort applies only when nothing is set.

**Trap:** This is the asymmetric-pod case Appendix A's mcq-1 already covered the throttle/OOM side of; this mcq-2 picks the QoS-class angle so the two MCQs from one source test genuinely different facets.

---

### 6. `k8s-010-mcq-1` — Networking (critical, easy, B2)

**Angle:** Service type selection — why ClusterIP is right for internal-only traffic.

**Distractor patterns:**
- D1 (NodePort for in-cluster discovery): *half-remembered* — knows NodePort opens a port, wrong about why.
- D2 (LoadBalancer with internal-only default): *real concept, wrong context* — internal LBs exist (via annotation) but aren't the default.
- D3 (ExternalName as cluster-internal CNAME): *adjacent technology confusion* — ExternalName works in reverse direction.

**Trap:** Candidates who've only used `kubectl expose --type=LoadBalancer` may reach for that out of habit.

---

### 7. `tf-002-mcq-2` — State (critical, medium, B3)

**Angle:** Sensitive data in state — the cleartext-in-state truth that surprises candidates.

**Distractor patterns:**
- D1 (sensitive = true encrypts state): *half-remembered* — the flag is about display, not storage.
- D2 (DynamoDB-derived envelope hash): *symmetric-but-wrong* — invents a mechanism that sounds plausible.
- D3 (provider memory only, not state): *what-the-candidate-wishes-were-true* — represents the wishful mental model.

**Trap:** A candidate who's only ever seen `sensitive = true` in the docs will assume it's an encryption flag.

---

### 8. `tf-011-mcq-1` — Configuration (medium, medium, B1)

**Angle:** count's positional-index addressing — the "remove the middle item" bug.

**Distractor patterns:**
- D1 (only index 2 destroyed): *half-remembered* — assumes Terraform tracks identity, not address.
- D2 (count can't shrink without state mv): *invented constraint* (a flavour of half-remembered) — sounds like a real restriction, isn't one.
- D3 (tail removal at index 4): *symmetric-but-wrong* — what intuition would suggest if count behaved like a stack.

**Trap:** The realistic candidate has read about count vs for_each but never hit this in production; the MCQ surfaces the muscle memory for it.

---

### 9. `cicd-020-mcq-1` — AWS integration (critical, medium, B1)

**Angle:** Why OIDC beats static keys — naming the real security improvement.

**Distractor patterns:**
- D1 (encryption in transit): *real concept, wrong context* — TLS already does this; the gap was the stored key.
- D2 (forced MFA): *adjacent technology confusion* — MFA is a separate IAM control, not what OIDC delivers.
- D3 (24h auto-rotation): *symmetric-but-wrong* — reframes "no key" as "frequent rotation" and misses the point.

**Trap:** Candidates who can spell OIDC but haven't reasoned about *what threat it actually closes* will pick whichever distractor sounds most security-flavoured.

---

### 10. `cicd-030-mcq-1` — Deployment strategies (critical, medium, B1)

**Angle:** Deploy strategy fit — when canary is specifically the right answer.

**Distractor patterns:**
- D1 (rolling update): *real concept, wrong context* — reduces risk but doesn't limit blast radius by percentage of users.
- D2 (blue-green): *real concept, wrong context* — fast rollback, but the cutover is all-or-nothing.
- D3 (recreate): *adjacent technology confusion* — fits the "extra infrastructure" cue inverted; recreate gives an outage window.

**Trap:** Candidates often treat rolling, blue-green, and canary as interchangeable risk-reducers — this MCQ separates them by the *type* of risk reduction.

---

## What I need from Stephen

Sign-off (or redlines) on:

1. **Quality bar match** — do all 10 hit the Appendix A bar (aws-002 / k8s-005 / tf-002 mcq-1 quality)? If any feel weaker, name them and I'll rewrite before Phase 3 starts.
2. **Distractor patterns** — any distractor that's *too easy* to dismiss (no Solutions Architect Associate candidate would pick it) or *too hard* (genuinely defensible as also correct)?
3. **Stem style** — I went heavier on scenarios than definitions (per brief 4.4). Right ratio, or should some be more direct?
4. **Subdomain naming** — I lowercased subdomain (e.g. `networking`, `iam`, `aws-integration`) per brief 5.2. Confirm.
5. **Pilot location** — currently at `interview-questions-runner/phase2-pilot/pilot.json`. Once approved I'll migrate these 10 plus the three Appendix A samples into the lab structure at `cloud-labs/lab-095-interview-drill-mcq/questions/`. Confirm that path.

Once approved I'll proceed to Phase 3: author the remaining ~195 MCQs in
batches of 20-30, run the validator against each batch, and surface any
calibration drift.
