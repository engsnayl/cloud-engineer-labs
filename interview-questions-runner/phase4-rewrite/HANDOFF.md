# Phase 4 — handoff (2026-06-03, TIER 1 + TIER 2 CLOSED; Tier 3 next)

## Headline state

- **TIER 1 + TIER 2 COMPLETE — committed and pushed to origin.** Branch `feat/lab-interview-drill-phase1` is up to date on the remote (Tier-2 HEAD `c2a9bfd`).
- **Tier 2 (T2.1) closed:** 25-item A-only slice → **23 swap items / 30 distractors swapped + 1 verify-no-change (`cicd-031-mcq-1`, FP) + 1 deferred to Tier-3 (`aws-022-mcq-1`)**. Rebaseline-12 split: 12/12 SWAP, 0 verify. Off-limits honoured (`cicd-020-mcq-2 d3` byte-identical). All A-only scope consumed — **there is no T2.2.**
- **86 Tier-1 stem reframes landed** across T1.1–T1.5; cumulative Tier-1 dropout 6/92 = 6.52%.
- **`borderline_approved` = 1** (`k8s-004-mcq-2`).
- **Next action: Tier 3 — Task 9, batch T3.1 (15 full reauthors).** Reslice is **LOCKED** (see "Tier 3 — locked reslice" below). Start in a FRESH window (full-rewrite tier; voice matters most). Resume from this doc + `tracking.json → tier3_reslice`.

## Tier 3 — locked reslice (Stephen 2026-06-03)

**Universe = 28 unique** = PLAN structural query (21) ∪ absorption queue (16); 9 overlap, 7 dropouts/deferrals are queue-only. PLAN's 13/8 rebalanced to **15/13** to absorb the 7 dropouts and slot `git-003-mcq-1` (no domain home in the PLAN slices). Full ID lists + cluster groupings live in `tracking.json → tier3_reslice`.

- **T3.1 (15):** aws struct (4) + `aws-021`,`aws-022` (superlative) + cicd struct (3) + `cicd-001` (compare) + k8s struct (5, i.e. 6 − `k8s-020`).
- **T3.2 (13):** tf struct (4) + `tf-012` + docker struct (3) + `docker-001`,`docker-007` + linux (1) + `k8s-020` + `git-003-mcq-1`.
- **Assignments:** `k8s-020-mcq-1` → T3.2 (honors prior assignment; option-balance is domain-light). `git-003-mcq-1` → T3.2 (compare-pair cluster; Git rode with Docker in T1.5).
- **Sequence rule (within each batch):** author by rewrite-pattern cluster as a run — compare-pairs → superlatives → multi-flag A+D → plain structural — so pattern application stays consistent across the domain-mixed batch.
- **Cross-tier source-distinctness:** every reauthor checks its same-`source_id` sibling against the **finalized** version wherever it now lives, not just in-batch. Specifically `git-003-mcq-1`'s reauthor must test a distinct facet from the already-committed `git-003-mcq-2` (T2.1).
- **Tier-3 shape:** full from-scratch reauthors (Task 9 procedure) — scenario stem + 4 options (≥2 of the 5 distractor patterns) + explanation ≤130 words; 6-month test on all 4 options; drop-out is "source doesn't decompose → surface for Stephen," not a stem revert.

## FRESH-SESSION read-back discipline for T3.1 (do before any authoring)

1. `git checkout feat/lab-interview-drill-phase1 && git pull`
2. **Fresh end-to-end pilot re-read — ALL 10 exemplars** (full reauthors touch every part; voice matters most this tier).
3. **Pilot-dupe pre-flight on the locked T3.1 (15 ids)** (`scripts/pilot_dupe_check.py`). (Dry-run at lock time: 0 matches.)
4. Surface the read-back and **HOLD** — no authoring until Stephen approves the read-back **and** the full Tier-3 bar is re-anchored.

## Tier-1 close-out numbers

| Batch | Slice | Reframes landed | Tier-3 / notes |
|---|---|---|---|
| T1.1 AWS | 17 | 15 | 1 Tier-3 (aws-021); +1 pilot-FP cleared (aws-026); 1 Tier-1.5 micro-edit (aws-009-mcq-2) |
| T1.2 K8s | 17 | 17 | 0 dropouts; 1 distractor → T2.1 (k8s-014-mcq-1), 1 → T3.2 (k8s-020) |
| T1.3 CI/CD | 16 | 15 | 1 Tier-3 (cicd-001) |
| T1.4 TF+Linux | 22 | 21 | 1 Tier-3 (tf-012); 3-way recall split, 0 intentional-recall exempt |
| T1.5 Docker+Git | 21 | 18 | 3 Tier-3 triaged at read-back; git-001 confirmed Tier-1 |
| **Total** | **93** | **86** | 6 Tier-3-needed + 1 pilot-FP cleared |

## Tier-3 absorption queue (7), grouped by cluster

Recorded in `tracking.json → tier3_absorption_queue` with per-item `cluster` tags.

**Cluster A — compare / definition-pair (5).** Shared rewrite pattern: rebuild the definition-pair options into **scenario-classifications** so the reasoning is load-bearing (the cicd-001 fix).
- `cicd-001-mcq-1` — CD vs Continuous Deployment distinction
- `tf-012-mcq-2` — `state mv` vs `import`
- `docker-001-mcq-1` — containers vs VMs isolation
- `docker-007-mcq-1` — named volumes vs bind mounts
- `git-003-mcq-1` — git clone vs GitHub fork

**Cluster B — superlative NOT-stem (1).** Positive reauthor.
- `aws-021-mcq-1` — "worst fit for Spot" → "best fit for Spot" with poor-fit distractors

**Cluster C — option-balance (1).** Stem already reframed; rebalance the length tell only.
- `k8s-020-mcq-1` — assigned to **T3.2** by Stephen (domain query would route to T3.1; honor the queue)

> NOTE on T3 batch slicing: the PLAN's locked T3.1/T3.2 slices predate this queue. When Tier 3 begins, reconcile the PLAN slices with this 7-item absorption queue (the compare/definition-pair cluster is a *new* shared-pattern grouping that emerged during Tier 1).

## Softening-check record (judgment/superlative items kept in Tier 1)

5 reframes carry a judgment/superlative frame but each has a **factual dominant answer**, so they sit at-bar (not softening the bank). All 5 are tagged in `tracking.json → running_totals.judgment_superlative_stayed_tier1` as **first distractor-review candidates for Tier 2**.

Three were not individually reviewed at their GATE — dominant-reason recorded here for the Tier-2 reviewer:

- **cicd-051-mcq-1** — *KEY:* "Fast signal first (parallelise + shard tests) and tighten the deploy gate (smaller batches, automated rollback) — speed of feedback is the dominant lever." *Dominant because:* compressing the feedback loop is the lever that reduces both speed and risk; the distractors (retries+disable-flakes, tooling churn, cut tests) each trade real signal for the appearance of progress.
- **k8s-014-mcq-1** — *KEY:* "Env vars are only set at pod startup, so any Service created after the pod is missing from the pod's environment until restart." *Dominant because:* the startup-only timing is the concrete, factual reason env-var discovery is weaker than DNS; the other options give wrong reasons. (Its `distractor_2` "32 entries per pod" is a confirmed fabrication → already in the Tier-2 widening queue.)
- **git-002-mcq-1** — *KEY:* "Require pull request reviews, require status checks to pass, restrict force pushes, and require linear history (or signed commits)." *Dominant because:* it's the only option that strengthens protection; the distractors each *weaken* it (admin bypass, CI force-push, disable-during-incident).

The other two (already reviewed at their GATEs): **cicd-051-mcq-2** (cleared at-bar), **git-001-mcq-1** (Tier-1 confirmed; see its Tier-2 note below).

## Queues carried into Tier 2

- **Tier-2 distractor widening (`tracking.json → tier2_widening_queue`):**
  - `k8s-014-mcq-1` / distractor_2 — replace fabricated "32 entries per pod" limit with a real env-var-discovery misconception. (Reclassified D→A in flagged-mcqs.json so the T2.1 query picks it up.)
  - `git-001-mcq-1` / distractor_2 (review all three) — all three distractors are false, so "strongest reason" over-promises; replace `distractor_2` ("rebase impossible in CI/CD" — filler) with a real-but-weaker legitimate reason (linear history / fewer integration points) so "strongest" is load-bearing. Stem stays as the confirmed Tier-1 reframe.

## Tier-2 starting state — Task 8, batch T2.1

**Goal:** swap A-only *fabricated* distractors for real misconceptions (or verify a flagged distractor as a genuine misconception → no change). Full procedure: PLAN.md Task 8.

**Scope is larger than the PLAN's original 11.** Re-derive the exact ID set at Tier-2 start:
1. Original 11 A-only (PLAN Task 8: AWS 4, CI/CD 4, K8s 2, Git 1).
2. **+12 rebaseline fabrications** (`tracking.json → rebaseline.new_fabrication_ids`): cicd-011-mcq-2, cicd-022-mcq-1, docker-004-mcq-2, git-003-mcq-2, linux-006-mcq-2, tf-010-mcq-2, cicd-022-mcq-2, cicd-012-mcq-2, docker-010-mcq-2, aws-019-mcq-2, cicd-021-mcq-1, tf-003-mcq-2.
3. **+ widening queue** (k8s-014-mcq-1, git-001-mcq-1 above).

Run the Task 8 Step 1 query (`A_fabricated` in flags) to get the live set, cross-reference `suspect-distractors.json`, and confirm the count before authoring. Tier-2 touches **only the named distractor** (and the explanation sentence that addresses it); stems stay as the Tier-1 reframes.

**Tier-2-specific drift:** also run `audit_suspect.py` and diff against the prior suspect set (PLAN Task 8 Step 5) — `check_drift.py` alone won't catch a newly-introduced suspect distractor.

## Required inputs (read in this order)

1. `interview-questions-runner/phase4-rewrite/HANDOFF.md` (this file)
2. `interview-questions-runner/phase4-rewrite/PLAN.md` — **operative rubric (lines ~13–37)** + Task 8 procedure
3. `interview-questions-runner/phase4-rewrite/tracking.json` — cumulative state, all queues
4. `interview-questions-runner/phase2-pilot/pilot.json` — the voice; **re-read end-to-end** (per-tier discipline; Task 8 Step 0)
5. `interview-questions-runner/phase3-audit/flagged-mcqs.json` + `suspect-distractors.json` — the A-flagged set
6. `cloud-labs/lab-095-interview-drill-mcq/questions/interview-{1,2,3}.json` — banks to edit
7. `Interview Prep App/Interview-Prep-Combined.md` (repo root) — source of truth for concepts

## Operative rubric pointer (settled at GATE 1; reinforced through Tier 1)

- **6-month-candidate test is the bar.** Named-identifier fabrications (invented keys/flags/commands/specific limits/version-deprecations) **fail categorically**. Invented-behaviour-of-a-real-feature **passes** if a junior could plausibly hold the misconception (transferred mental model / natural mis-extension); **fails** on impossibilities, false-authority jargon, or contradicting basic semantics.
- **Compare / definition-pair triage (new in T1.5):** any item whose ask is an abstract comparison ("how does X differ from Y" / "distinguish X from Y") **and** whose options are definition-pairs → Tier-3 (rebuild options into scenario-classifications). Functional-selection over concrete-artifact options stays Tier-1 (`linux-002-mcq-1` is the reference for what stays).
- **Superlative/comparative framings** are at-bar when the property has a factual answer; not at-bar when "strongest/worst" reduces to contestable opinion (→ Tier-3).
- **Borderlines → surface with a recommendation; don't auto-decide.**

## Things to NOT forget

- **Re-read pilot end-to-end before authoring** (per-tier discipline; Task 8 Step 0) — even though Tier 2 swaps distractors rather than stems, the pilot's per-distractor reasoning is the bar.
- **Pilot-dupe pre-flight** on the slice (`scripts/pilot_dupe_check.py`).
- **Match bank JSON format** when applying: `apply_batch.py <batch.json>` (writes `after` for completed, `before` for dropped; ensure_ascii=True, indent=2, CRLF — keeps the diff to changed lines only).
- **Per-batch GATE:** surface checkpoint, hold commit until Stephen approves.
- **draft-audit.json** is regenerated by every drift run — do **not** stage it; it's not in any batch's commit scope. The `"Interview Prep App/"` source dir is read-only and also unstaged.
- **Helpers (committed):** `scripts/check_drift.py`, `scripts/pilot_dupe_check.py`, `phase4-rewrite/apply_batch.py`.
