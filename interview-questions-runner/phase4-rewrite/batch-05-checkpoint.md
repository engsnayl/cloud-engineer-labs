# Batch T1.5 checkpoint — TIER-1 CLOSE-OUT

**Tier:** 1  **Slice:** Docker (13) + Git (8) D-only  **Date:** 2026-06-03

## Audit script result on batch

- Drift check: **PASS** — `{touched_count: 18, touched_still_flagged: [], regressions: [], result: "PASS"}`
- New audit re-flags on touched IDs: none
- Validate script: **PASS** (interview-1/2/3.json all exit 0; only pre-existing option-length soft warnings)
- Pilot-dupe pre-flight: 0 byte-identical (no docker/git pilot exemplars exist)
- Pre-apply `classify_stem()`: all 18 Tier-1 stems classify `scenario`, 0 trip C-flag
- **docker-006-mcq-1 stem-wording check (Stephen 2026-06-03):** first reframe used "port mapping" (tripped the match-style regex), then "port-translation layer" (risked reading as coined vocabulary). Final wording uses Docker's standard verb: *"…with no NAT and no separate port-publishing step."* Reads as plain description, classifies `scenario`, options untouched.
- Bank diff scope: exactly 18 `question` lines; options + explanation byte-identical

## New triage step applied at read-back (Stephen 2026-06-03)

Pre-flag any item whose ask is an abstract comparison ("how does X differ from Y" / "distinguish X from Y") **and** whose options are definition-pairs → route straight to Tier-3, do not author a Tier-1 reframe. **3 routed this way** (confirmed by Stephen before authoring):

| ID | Ask | Why Tier-3 |
|---|---|---|
| docker-001-mcq-1 | "isolation mechanism that makes containers different from VMs" | definition-pair options (each defines both) |
| docker-007-mcq-1 | "Compare named volumes and bind mounts" | definition-pair options — tf-012 shape |
| git-003-mcq-1 | "What's the difference between git clone and a GitHub fork" | definition-pair options — exact cicd-001 signature |

The triage step is working: these 3 were caught **before** authoring effort, vs cicd-001/tf-012 which were caught only after authoring + at the GATE.

## Session context status

- Estimated context usage: ~55–60% (in the handoff band)
- Handoff recommended: **YES** — per your instruction, a fresh window for Tier 2 regardless of level. Handoff doc to be written after the git-001 ruling, before any Tier-2 authoring.

## ✅ RULED — git-001-mcq-1 Tier-1 CONFIRMED (Stephen 2026-06-03)

Authored as a provisional Tier-1 reframe; **confirmed Tier-1, reframe kept.** Logged a Tier-2 distractor-strengthening note: all three distractors are false, so "strongest reason" over-promises and distractor_2 ("rebase impossible in CI/CD") is filler — replace with a real-but-weaker legitimate reason at Tier 2 so "strongest" becomes load-bearing (in `tracking.json → tier2_widening_queue`; no action now).

**Reframed stem:**
> An engineer is integrating a feature branch into `main` and is weighing `git merge` against `git rebase`. Which is the strongest reason to prefer `git merge`?

**Options (unchanged):**
- **correct (keyed):** Merge preserves the actual history of when changes happened, which is valuable for archaeology and debugging long after the merge
- distractor_1: Merge is faster than rebase on large repositories because rebase rewrites every commit individually
- distractor_2: Merge avoids creating new commit SHAs for existing commits, which makes rebase impossible to use in CI/CD pipelines
- distractor_3: Merge is the only way to combine two branches; rebase merely moves commits between branches without combining their changes into the target branch's history

**Against your ruling test (superlative clause, not the definition-pair test):**
- The keyed reason is "merge preserves true history." The three distractors are each **objectively wrong**, not competing legitimate reasons: d1 (merge faster — false), d2 (rebase impossible in CI/CD — false), d3 (merge is the only way to combine — false). There is **no rival legitimate reason** (e.g. "linear history", "fewer integration points") sitting in the option set competing on taste.
- So by your test this reads **AT-BAR / Tier-1 confirmed**: the keyed reason is the only defensible one present and the distractors are clearly weaker/wrong — "strongest" does not reduce to contestable opinion here. My recommendation: **confirm Tier-1**. (Your call governs.)

## TIER-1 CLOSE-OUT

### 1. Total Tier-1 reframes landed (T1.1–T1.5)

| Batch | Slice | Reframes landed | Notes |
|---|---|---|---|
| T1.1 AWS | 17 | 15 | +1 pilot-FP cleared (aws-026), 1 Tier-3 (aws-021) |
| T1.2 K8s | 17 | 17 | 0 dropouts; 1 distractor → T2.1, 1 → T3.2 |
| T1.3 CI/CD | 16 | 15 | 1 Tier-3 (cicd-001) |
| T1.4 TF+Linux | 22 | 21 | 1 Tier-3 (tf-012); 3-way recall split, 0 exempt |
| T1.5 Docker+Git | 21 | 18* | 3 Tier-3 triaged at read-back |
| **Total** | **93** | **86*** | *18 incl. git-001 provisional |

(93 slice = 86 reframed + 6 Tier-3-needed + 1 pilot-FP cleared; note T1.1's 17 slice contributed 16 reframe-attempts after the FP.)

### 2. Full Tier-3 absorption queue (7), grouped

**Cluster A — compare / definition-pair (shared rewrite pattern: rebuild options into scenario-classifications):**
- cicd-001-mcq-1 (T1.3) — CD vs CDep distinction
- tf-012-mcq-2 (T1.4) — state mv vs import
- docker-001-mcq-1 (T1.5) — containers vs VMs isolation
- docker-007-mcq-1 (T1.5) — named volumes vs bind mounts
- git-003-mcq-1 (T1.5) — git clone vs GitHub fork

**Cluster B — superlative NOT-stem (positive reauthor):**
- aws-021-mcq-1 (T1.1) — "worst fit for Spot" → "best fit for Spot" + poor-fit distractors

**Cluster C — option-balance (rebalance length tell; stem already reframed):**
- k8s-020-mcq-1 (T1.2) — assigned to T3.2 per your earlier instruction

(If you route git-001-mcq-1 to Tier-3, it joins as a Cluster-B-like superlative item → queue size 8.)

### 3. Final cumulative Tier-1 dropout rate

- **6 of 92 reframe-attempts = 6.52%** — well under the 20–30% estimate.
- Sub-counts (per your instruction, both count as "needed Tier-3"):
  - **Triaged at read-back:** 3 (docker-001-mcq-1, docker-007-mcq-1, git-003-mcq-1)
  - **Authored then dropped:** 3 (aws-021-mcq-1, cicd-001-mcq-1, tf-012-mcq-2)
- **PROVISIONAL** pending git-001 ruling: becomes **7 of 92 = 7.61%** (authored-then-dropped → 4) if you route git-001 to Tier-3.
- Also tracked off the dropout rate, per the rules: 1 pilot-FP cleared (aws-026), 0 intentional-recall exemptions, 1 distractor widened to T2.1 (k8s-014-mcq-1).

### 4. Judgment/superlative items that STAYED Tier-1 (bank-softening sanity check)

5 items (4 confirmed + 1 provisional). Each retains a factual dominant answer, so they sit at-bar rather than softening the bank:
- cicd-051-mcq-1 (T1.3) — "mature production thinking" prioritisation
- cicd-051-mcq-2 (T1.3) — "most likely lesson from 18 months" (cleared at its GATE)
- k8s-014-mcq-1 (T1.2) — "weaker option" comparative (factual, wrong-reason distractors)
- git-002-mcq-1 (T1.5) — "strongest baseline" branch protection (factual combination)
- git-001-mcq-1 (T1.5) — "strongest reason to prefer merge" (**provisional**)

5 of 86 reframes (~6%) carry a judgment/superlative frame, all with a defensible single answer — no evidence of systematic softening.

## borderline_approved counter

Confirmed **still 1** (`k8s-004-mcq-2` only) — unchanged across all of Tier 1. No invented-identifier-as-transferred-model cases beyond the original; the bar was never hit for a mid-flight revisit.

## Decision (Stephen, 2026-06-03)

1. **git-001-mcq-1 — Tier-1 CONFIRMED.** Reframe kept; Tier-2 distractor-strengthening note logged.
2. **Close-out APPROVED.** Final: 86 Tier-1 reframes, 6/92 = 6.52% dropout, Tier-3 queue of 7 (6 Tier-1 dropouts + k8s-020 independently routed). T1.5 = 18 reframes.
3. **docker-006-mcq-1** reworded to standard Docker phrasing (see above).

Tier 1 is **closed**. Committed + pushed; handoff doc written. Tier 2 begins in a fresh window off the handoff — no Tier-2 authoring in this context.
