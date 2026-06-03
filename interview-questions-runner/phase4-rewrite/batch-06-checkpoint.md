# Batch T2.1 checkpoint

**Tier:** 2  **Slice:** A-only fabricated-distractor swaps (AWS, CI/CD, Docker, Git, K8s, Linux, TF)  **Date:** 2026-06-03

> First Tier-2 batch — **full calibration surface**: every swap-in and every verify-no-change is listed below with new text, a one-line plausibility rationale, the rewritten explanation sentence, and an **AT-BAR** / **BORDERLINE** tag. You rule on borderlines; the clear ones are for calibration. T2.2+ revert to borderlines-only.

## Audit script result on batch

> **Updated after Stephen's B1–B4 rulings (2026-06-03):** B1 reverted+deferred, B2 reworked, B3 accepted, B4 widened. Numbers below are final.

- **Drift check:** PASS — `touched_count=24, touched_still_flagged=[], regressions=[]` (aws-022 excluded as deferred per B1).
- **Validate (all 3 banks):** PASS (exit 0). Only soft length-balance warnings remain, all on **pre-existing untouched** MCQs. (The first run flagged `git-001-mcq-1` over the 130-word explanation cap and two `always` absolute-word tells; both fixed.)
- **Tier-2 `audit_suspect.py` diff (touched IDs):** 7 rows —
  - **6 pre-existing**, all on distractors I deliberately **kept** as at-bar transferred-misconceptions (documented over-flag): `cicd-021-d3`, `cicd-020-d3` (off-limits FP), `docker-010-d2`, `cicd-011-d1`, `git-006-d3`, `k8s-031-d2`.
  - **1 newly-introduced FP:** `cicd-020-mcq-2 d2` (my new `aud` distractor) trips `specific-domain-path` because it contains **`sts.amazonaws.com`** — the *real* default GitHub-OIDC audience. Heuristic FP on a real identifier (same class as `aws:MultiFactorAuthPresent`), **not** a fabrication. Recorded under `tracking.json → heuristic_fp_classes.suspect_real_identifier_introduced`. No rework. (`git-003-d3`'s self-introduced `auto-implicit` FP was cleared by rewording during the B4 widening.)

## Session context status

- Estimated context usage: **under 50%** (~25–30%).
- Handoff recommended: **no** — comfortable headroom remaining.
- Notes: single session; all read-back inputs + authoring of 25 items in this window.

## Self-assessment numbers

- MCQs attempted: **25** (24 A_fabricated live + git-001 widening).
- Swaps applied (final): **23 items / 30 distractors** (26 confirmed categorical fabrications + 1 over-claim tightened [cicd-002] + 3 git-001 misconceptions).
- Verify-no-change (FP confirmed at-bar): **1** (`cicd-031-mcq-1`).
- Deferred to Tier-3 (B1): **1** (`aws-022-mcq-1`, reverted to original).
- Multi-distractor items: `aws-019` (3, all were fabricated), `git-001` (3), `k8s-031` (2), `linux-006` (2), `git-003` (2, d3 widening per B4).
- Widenings actioned: `k8s-014-mcq-1`, `git-001-mcq-1` (queued), `git-003-mcq-2/d3` (B4), `k8s-031-mcq-2/d3` (B3 detector-gap).

## Scope reconciliation (25-set)

24 live `flags == ['A_fabricated']` = 11 original (AWS 4, CI/CD 4, K8s 2, Git 1) + 12 rebaseline + `k8s-014` (reclassified D→A) — **+ git-001-mcq-1** (widening, not flag-reclassified, added manually). The **8 multi-flag A+D** items are deferred to Tier-3 per your ruling (see end).

---

## Calibration — ALL swap-ins

Format: **`id` — key** → new distractor · *why a 6-month candidate believes it* · explanation sentence now reads: "…" · **TAG**

### AWS

- **`aws-016-mcq-2` — d3** → "The DNS record's TTL hasn't expired yet, so resolvers are still returning the cached primary record even though Route 53 has already failed over at its end" · *DNS TTL caching is a real failover-delay cause a junior would reach for* · *"Distractor 3 reaches for DNS TTL caching — a real failover-delay cause — but here Route 53 never flipped at all (no health check is attached), so there's nothing cached to expire."* · **AT-BAR**
- **`aws-019-mcq-2` — d1, d2, d3** (all three were fabricated post-resize mechanisms) →
  - d1: "The stop/start required to resize the instance cleared the OS page cache, so the application stays slow until its filesystem caches warm back up" · *resize really does stop/start → cold cache is real, but transient*
  - d2: "m5.large and m5.xlarge run on the same hardware generation, but the larger size has more vCPUs at the same per-core clock, so any single-threaded hot path runs no faster and added lock contention can slow it" · *"more cores = slower per-core / more contention" is a common model*
  - d3: "Doubling the vCPUs splits the instance's fixed network and EBS bandwidth across more cores, so per-core I/O throughput dropped after the resize" · *"fixed pool divided among more cores" inversion (AWS actually scales bandwidth up)*
  - expl now names each: cold-cache (transient), same-clock/contention, bandwidth-inversion. · **AT-BAR** *(3-distractor scope; Stephen pre-commit hold 2026-06-03 resolved: stem is the slower-after-resize form with the real-slowdown key, so d2's true "single-threaded" clause is context not the keyed reason — no rework; stem's settled-50%-CPU "now slower" establishes steady-state slowness, so d1's transient cold-cache is distinguishably wrong)*
- **`aws-031-mcq-2` — d3** → "Restarting wipes the CloudWatch metric history for the instance, so you'd lose the record of the spike needed for the post-incident review" · *juniors think restarting erases monitoring data; CloudWatch retains it* · *"Distractor 3 assumes restarting erases CloudWatch history — but CloudWatch stores metrics as durable time-series independent of the process; what you actually lose by restarting is the live process state (thread dumps, the running JIT profile), not the recorded metrics."* · **AT-BAR**
- **`aws-035-mcq-1` — d1** → "REST API — it's the more mature option; HTTP API still doesn't support custom domain names or TLS certificates, so it can't serve production traffic on a branded endpoint" · *"newer/simpler must lack enterprise features" (HTTP API has had custom domains + ACM from launch)* · *"Distractor 1 leans on a 'newer means less capable' assumption — but HTTP API has supported custom domain names and ACM TLS certificates since launch, so the branded-endpoint objection is false."* · **AT-BAR**
- **`aws-022-mcq-1`** → **DEFERRED to Tier-3 (B1 ruling)** — distractor swap reverted, bank restored to original. The "WORST fit" stem needs a best-fit reauthor (inverts keying, reshuffles options); the fabricated Fargate 15-min-timeout distractor is replaced as part of that whole-item Tier-3 reauthor, in the superlative cluster alongside `aws-021`.

### CI/CD

- **`cicd-002-mcq-2` — d1** → "Upgrade to the largest available runner tier so the whole pipeline runs on more CPU and memory" · *throwing a bigger runner at slow CI is a near-universal instinct (CI is mostly I/O-bound)* · *"Distractor 1 throws hardware at the problem — a real instinct, but most CI time is I/O-bound (dependency installs, network, serial test ordering), so a bigger runner barely moves a 25-minute pipeline; the win is parallelism, not raw size."* · **AT-BAR** *(this one only dropped the false "scales linearly" absolute; the instinct was already a real misconception)*
- **`cicd-011-mcq-2` — d3** → "Composite actions can use secrets only if the action's YAML lives in the same repository as the calling workflow; actions referenced from another repository are blocked from all secrets" · *juniors assume cross-repo/third-party actions can't get secrets* · *"Distractor 3 ties secret access to where the action lives — but a composite action receives secrets through explicit input passing regardless of which repository hosts it; location isn't the gate."* · **AT-BAR**
- **`cicd-012-mcq-2` — d3** → "Set `fail-fast: false` in the strategy so the flaky macos+node18 combination still runs but no longer cancels the other matrix jobs when it fails" · *real matrix setting confused with "remove a combo"* · *"Distractor 3 reaches for `fail-fast: false` — a real strategy setting, but it only stops one leg's failure from cancelling the others; the macos+node18 job still runs, so nothing is skipped."* · **AT-BAR**
- **`cicd-013-mcq-2` — d1** → "Just push the built image to a registry each run and pull it at the start of the next build — Docker reuses the pulled image's layers as the build cache automatically, no cache flags needed" · *very common belief that push-then-pull gives layer caching for free* · *"Distractor 1 assumes pulling a previously-pushed image seeds the build cache for free — but BuildKit won't treat a pulled image as cache unless you point `--cache-from` at it (or built it with inline cache); a plain pull doesn't populate the layer cache."* · **AT-BAR**
- **`cicd-020-mcq-2` — d2** (d3 MFA OFF-LIMITS, left byte-identical) → "An `aud` (audience) condition requiring the token's audience to equal `sts.amazonaws.com`, which ties the role to your repository's OIDC identity" · *classic aud-vs-sub mix-up; aud is identical across all repos so it can't scope* · *"Distractor 2 pins the `aud` claim — but GitHub issues the same `sts.amazonaws.com` audience to every repository, so it can't distinguish yours; only a `sub` condition scopes the trust."* · **AT-BAR** *(the swapped-out d2 was an impossible `MaxSessionDuration` of 600s — below the real 3600s floor)*
- **`cicd-021-mcq-1` — d1** → "kubectl apply has no way to preview changes before they hit the cluster, whereas Helm can show a diff first — so apply is unsafe for production changes" · *juniors think only Helm can preview; kubectl has `diff`/`--dry-run=server`* · *"Distractor 1 claims kubectl can't preview changes — but `kubectl diff` and `--dry-run=server` both show pending changes before they apply, so the preview gap is imaginary."* · **AT-BAR**
- **`cicd-022-mcq-1` — d3** → "An in-place restart: ECS pulls the new image into each running task and restarts the container inside it, reusing the existing task instances rather than launching new ones" · *transferred "docker restart" model; ECS tasks are immutable* · *"Distractor 3 imagines ECS mutating tasks in place — but ECS tasks are immutable; a new revision always launches fresh tasks and stops the old ones, never restarts a container inside an existing task."* · **AT-BAR**
- **`cicd-022-mcq-2` — d1** → "Set the rolling update's maximumPercent to 200 so ECS stands up a full second set of new tasks alongside the old ones, then cuts all traffic over at once when they're healthy" · *`maximumPercent: 200` is real and surges to 2× capacity; confused with blue/green one-cut* · *"Distractor 1 reaches for `maximumPercent: 200` — a real setting that does run double capacity — but a rolling update still drains old tasks gradually rather than cutting over in one atomic switch, and there's no built-in automated rollback."* · **AT-BAR** *(swapped-out d1 was the impossible `minimumHealthyPercent: 200`)*
- **`cicd-031-mcq-1`** → **VERIFY-NO-CHANGE** (see verify section).

### Docker / Git

- **`docker-004-mcq-2` — d2** → "A `.gitignore` file listing node_modules, .git, and .env — docker build reads `.gitignore` and excludes those paths from the build context automatically" · *classic: assume docker honours `.gitignore` like other tools; it only reads `.dockerignore`* · *"Distractor 2 assumes docker reuses `.gitignore` — but `docker build` only honours `.dockerignore`; a `.gitignore` has no effect on the build context."* · **AT-BAR**
- **`docker-010-mcq-2` — d3** → "The application writes to stderr rather than stdout, and `docker logs` only captures stdout — so the error output exists but isn't shown" · *common belief stdout/stderr are handled separately; `docker logs` captures both* · *"Distractor 3 assumes `docker logs` shows only stdout — but it captures both stdout and stderr, so a silent container isn't hiding output on the 'wrong' stream; it's exiting before it logs anything."* · **AT-BAR**
- **`git-003-mcq-2` — d2 + d3** (d3 swapped per **B4** widening) →
  - d2: "Repoint `origin` at the original repository with `git remote set-url origin <upstream-url>`, then `git pull` to sync from upstream" · *real remote-management mistake: point origin at upstream to "get updates," silently breaking your fork as a push target*
  - d3 (B4): "Use GitHub's 'Sync fork' button — it updates your fork on GitHub and adds the `upstream` remote to your local clone, so a plain `git fetch` then pulls upstream's changes" · *old d3 ("GitHub auto-reroutes the push") was an invented feature; new d3 uses the REAL Sync-fork button but misplaces it as a local-remote configurator (it runs server-side)*
  - · **AT-BAR (B4 resolved)**
- **`git-006-mcq-2` — d1** → "Add the file to `.gitignore` and push the change — Git stops tracking the file and drops it from the earlier commits where the key appeared" · *widespread "`.gitignore` removes already-committed files / scrubs history" misconception* · *"Distractor 1 expects `.gitignore` to rewrite history — but it only stops future additions of untracked files; the key stays in every commit it was already part of."* · **AT-BAR**
- **`git-001-mcq-1` — d1, d2, d3** (logged Tier-2 strengthening; **d2 reworked per B2**; keyed answer unchanged) →
  - d1: "Merge is safer because an interrupted rebase can permanently lose commits, while a merge is straightforward to undo" · *common fear that interrupted rebase loses commits (reflog/ORIG_HEAD recover) — genuinely wrong, not a real advantage*
  - d2 (B2): "Merge resolves most conflicts automatically, whereas rebase forces you to resolve every conflict by hand" · *believable "merge is the easy path" belief, but genuinely FALSE — both surface the same conflicts; no longer a near-second-correct, so "strongest" is decisive*
  - d3: "Merge keeps the feature branch's commits exactly as written, while rebase squashes them into a single commit on top of main" · *very common rebase=squash conflation — genuinely wrong*
  - explanation rewritten end-to-end (≤130 words). · **AT-BAR (B2 resolved)**

### Kubernetes / Linux / Terraform

- **`k8s-014-mcq-1` — d2** (keyed startup-time reason preserved as factual-dominant) → "Env vars uppercase the Service name and convert dashes to underscores, so a Service like `my-api` is silently unreachable through env-var discovery because the transformed name no longer matches" · *the dash→underscore/uppercase transform is real; wrong conclusion that it makes dashed names unreachable* · *"Distractor 2 points at the real name transform (dashes become underscores, name uppercased) but draws the wrong conclusion — the transformed variable `MY_API_SERVICE_HOST` is still populated and usable, so dashed Service names aren't lost."* · **AT-BAR** *(verified: keyed answer stays uniquely correct & factual-dominant)*
- **`k8s-031-mcq-2` — d1 + d3** (two swaps) →
  - d1: "ESO's ServiceAccount lacks Kubernetes RBAC permission to create Secret objects, so the controller can't write the synced secret into the cluster" · *conflating K8s RBAC with AWS IAM (RBAC gap fails K8s-side, not as an AWS AccessDenied)*
  - d3: "The Secrets Manager secret needs a resource policy that explicitly allows the cluster's OIDC provider as a principal — without it, same-account reads are denied" · *resource policies are real but only needed cross-account*
  - expl rewritten for both. · **BORDERLINE — see B3 (d3 is a fabrication beyond the flagged-mcqs-named d1; AccessDenied distractor space is hard)**
- **`k8s-051-mcq-2` — d3** → "HPA scaling events — each time the Horizontal Pod Autoscaler adds a replica, the Service briefly pauses in-flight requests while its endpoints are updated, producing the periodic spikes" · *plausible belief autoscaling interrupts traffic during endpoint updates (it's non-disruptive)* · *"Distractor 3 blames HPA scaling — but adding a replica only appends endpoints; it doesn't pause or reroute in-flight requests, so scaling events don't produce per-request latency spikes."* · **AT-BAR** *(swapped-out d3 was the Stephen-flagged Istio ~450ms)*
- **`linux-006-mcq-2` — d1 + d3** (two swaps, both were invented-flag fabrications) →
  - d1: "`journalctl -u nginx -f -p crit`" · *priority-level confusion: `crit` looks "stricter" but drops the `err` level the task needs*
  - d3: "`journalctl -u nginx -p err | tail -f`" · *common shell belief that piping into `tail -f` adds following; journalctl needs its own `-f`*
  - expl rewritten for both. · **AT-BAR**
- **`tf-003-mcq-2` — d2** → "A `version` argument in the module block (e.g. `version = \"~> 1.2.0\"`) to constrain which release of the Git module Terraform pulls" · *very common: `version` works only for registry modules; Git sources pin with `?ref=`* · *"Distractor 2 reaches for the `version` argument — real, but it only works for registry modules; for a `git::` source Terraform rejects it, and you must pin with `?ref=` instead."* · **AT-BAR**
- **`tf-010-mcq-2` — d3** → "An `aws_ami_copy` resource that imports the Packer-built AMI into your Terraform state, after which you reference it by ID" · *`aws_ami_copy` is real but copies/re-encrypts an AMI; mistaken for the Packer handoff (which is a data-source lookup)* · *"Distractor 3 reaches for the real `aws_ami_copy` resource — but that duplicates an existing AMI (cross-region or re-encryption); it doesn't look up a Packer build, which is what the data source does."* · **AT-BAR**

---

## Verify-no-change (positive at-bar claim, full scrutiny)

- **`cicd-031-mcq-1` — d2** (kept byte-identical): "Run the rename online using ALTER TABLE; PostgreSQL/MySQL handle column renames as metadata-only operations with no downtime."
  - **Why genuinely at-bar:** "a column rename is a metadata-only, no-downtime ALTER TABLE" is a real, widely-held belief — and partly *true* at the DB layer (Postgres/MySQL renames are fast/metadata). It's **wrong for this scenario** because the 50 running web servers still reference the old column name, so the rename breaks their in-flight queries atomically — exactly what expand-contract avoids. **No invented identifier.** Closer to the `tf-011` (pass) anchor than `tf-002-d2` (fail).
  - **Heuristic recommendation:** the `A_fabricated` flag here is a false positive — keep the distractor; the suspect/LLM pass over-fired on a true-at-the-DB-layer claim. · **AT-BAR (FP)**

---

## Borderlines — RESOLVED (Stephen rulings 2026-06-03)

- **B1 — `aws-022-mcq-1`:** **REVERTED + deferred to Tier-3 Cluster B (superlative)** alongside `aws-021`. The worst-fit stem needs a best-fit reauthor that inverts keying and reshuffles options, so a distractor swap now is orphaned work; Tier-3 replaces the fabrication as part of the whole-item reauthor. Bank restored to original.
- **B2 — `git-001-mcq-1` d2:** **REWORKED.** "Resolve a conflict once" was a *true* merge advantage → near-second-correct under a "strongest reason" stem. Replaced with a genuinely-wrong misconception ("merge resolves most conflicts automatically, rebase doesn't" — both are manual). d1/d3 confirmed genuinely wrong (not real advantages). Keyed answer unchanged.
- **B3 — `k8s-031-mcq-2`:** **ACCEPTED both swaps.** d3 recorded as an explicit widening; **detector-coverage gap** logged (`tracking.json → detector_coverage_gaps`) — flagged-mcqs named only d1 but d3 also fabricated a named annotation.
- **B4 — `git-003-mcq-2` d3:** **SWAPPED as a widening** ("GitHub auto-reroutes the push" was an invented feature, fabrication pole) → Sync-fork-button-is-server-side misconception.

## Rebaseline-12 swap-vs-verify split (over-flag signal)

All **12/12 rebaseline fabrications were SWAP, 0 verify-no-change** — i.e. every heuristic-review/LLM-pass/control-sample addition was a genuine fabrication on review. The over-flag risk from the expanded audit did **not** materialise on this slice (contrast: the *constraint/mechanism* heuristics still over-flag the at-bar distractors I kept — 7 of them — consistent with the documented "useful contrast signal, not a verdict" finding).

## Off-limits confirmation

- **`cicd-020-mcq-2` distractor_3 (MFA-inheritance):** left **byte-identical** — not touched. Only d2 was swapped. ✔

## Tier-3 queue addition

The **8 deferred multi-flag A+D** items were added to `tracking.json → tier3_absorption_queue` as a new **`multi_flag_a_plus_d`** cluster (each carries an unresolved D stem *and* an A distractor → whole-item rewrite): `docker-002-mcq-2, docker-009-mcq-2, k8s-001-mcq-2, k8s-011-mcq-1, k8s-021-mcq-2, k8s-041-mcq-2, tf-005-mcq-1, tf-009-mcq-1`. Tier-3 queue size: 7 → **15**.

## Decision requested

B1–B4 **ruled and applied**; calibration sample surfaced. Awaiting final **approve** to commit.

**Commit scope (4 files):** `batch-06-tier2.json`, `batch-06-checkpoint.md`, `tracking.json`, and the 3 bank files (`interview-{1,2,3}.json`).
**Excluded:** `draft-audit.json` + `suspect-distractors.json` (regenerated artifacts); `build_batch_06.py` (one-shot generator — kept locally, **discarded from commit scope** per Stephen).
