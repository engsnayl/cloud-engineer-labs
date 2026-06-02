# Phase 4 — handoff (2026-06-02, T1.1 + T1.2 committed)

## Headline state

- **Tier 1 in progress: 2 of 5 batches done and committed** (T1.1 AWS, T1.2 Kubernetes).
- **33 stem reframes total** (15 AWS + 17 K8s + 1 AWS Tier-1.5 micro-edit counted within the 15), **1 Tier-3 dropout** (aws-021-mcq-1), **3 pilot-FPs cleared**, **3 borderlines adjudicated**.
- **Cumulative Tier-1 dropout rate: 3.03%** (1 of 33 reframe-attempts) — well under the 20–30% estimate. Honest: D-only flags mark a missing scenario-actor marker, not a content defect, so adding an actor disturbs nothing.
- **Flagged total: 135** (was 138; −3 pilot byte-identical FPs in T1.1). Reframed D-only MCQs stay on the worklist as resolved-in-place (verified by drift + final audit), per the plan's model.
- **Next action: Tier 1 continues — Task 5, batch T1.3 (CI/CD D-only). Slice = 16** (see correction below). No T1.3 work has started.

## Correction to the prior session's estimate

The prior handoff guidance guessed T1.3 ≈ 15 ("16 − cicd-020-mcq-1 cleared"). **That's wrong:** `cicd-020-mcq-1` was flagged `C_never_correct` (a pilot FP, cleared in T1.1), **not** `D_definition`, so it was never in the CI/CD D-only slice. **The CI/CD D-only slice is 16.** Confirm at session start with the Task 5 query.

## What happened this session

### T1.1 — AWS D-only (committed `fee5e5e`)
- 17-MCQ slice → **15 reframed** (14 pure Tier-1 + 1 Tier-1.5: `aws-009-mcq-2` distractor_1 spelling `--multi-attach=true` → `--multi-attach-enabled=true`), **1 dropped to Tier 3** (`aws-021-mcq-1`, "worst candidate" superlative = structural NOT-stem), **1 cleared FP** (`aws-026-mcq-1`).
- Established the **`pilot_byte_identical` FP class**: bank MCQs byte-identical to a pilot exemplar auto-clear (they ARE the bar). Global scan cleared 3: `aws-026-mcq-1`, `cicd-020-mcq-1`, `k8s-010-mcq-1`. flagged-mcqs.json 138→135.
- New tool `scripts/pilot_dupe_check.py` + pre-flight step + D_definition mechanism note added to PLAN.md.

### T1.2 — Kubernetes D-only (committed this session)
- Slice was **17** (was 18; `k8s-010-mcq-1` already cleared in T1.1). All **17 reframed**, 0 dropouts.
- 3 borderlines adjudicated by Stephen:
  - `k8s-004-mcq-2` — **at-bar** (invented field names = transferred-mental-model). In `tracking.json → borderline_approved`.
  - `k8s-014-mcq-1` — d2 "32 entries per pod" = **fabrication → Tier 2** (widens T2.1; reclassified D→A in flagged-mcqs.json). "Weaker than" framing **kept**; rubric distinction added to PLAN.md.
  - `k8s-020-mcq-1` — **Tier-3 option-balance → T3.2** (one-word-correct vs verbose-distractor length tell; reclassified D→B_structural).

## Queues carried forward

- **Tier 3 absorption (`tracking.json → tier3_absorption_queue`):**
  - `aws-021-mcq-1` — full positive reauthor ("best fit for Spot" + poor-fit distractors).
  - `k8s-020-mcq-1` — option-balance pass only (stem already reframed). Stephen assigned to **T3.2** (domain-query would otherwise route it to T3.1 — honor the queue).
- **Tier 2 widening (`tracking.json → tier2_widening_queue`):**
  - `k8s-014-mcq-1` / distractor_2 — replace fabricated "32 entries" limit. T2.1 widens beyond the original 11 A-only (plus the 12 rebaseline fabrications already noted).

## Exact next action for the new session

**Task 5 — batch T1.3: reframe the 16 CI/CD D-only MCQ stems to scenario form.** Follow `PLAN.md` Task 5 (identical procedure to Task 3). In brief:
- **Step 0:** re-anchor on `phase2-pilot/pilot.json` (re-read end-to-end — per-tier discipline rule). CI/CD pilot voice: `cicd-020-mcq-1` (OIDC vs static keys) and `cicd-030-mcq-1` (canary/blast-radius).
- **Step 0.5 (pre-flight):** `python interview-questions-runner/scripts/pilot_dupe_check.py <slice-ids>` — clear any byte-identical-to-pilot before authoring.
- **Step 1:** confirm the 16 IDs: `flags == ['D_definition'] and domain == 'cicd'`.
- **Authoring:** lead each reframe with a recognised scenario-actor marker (see the D_definition mechanism note in PLAN.md) so the flag clears. CI/CD-specific fodder: OIDC vs static credentials, workflow/job/step scope, runner types, artifact retention.
- **Verify:** `validate_mcqs.py` (3 banks) → `check_drift.py batch-03-tier1-cicd.json` must PASS → update tracking.json → `batch-03-checkpoint.md` → **surface to Stephen (GATE)** → commit after approval.
- **Watch:** the `borderline_approved` counter — if Tier 1 hits 3+ invented-identifier-as-transferred-model cases, flag to revisit the bar mid-flight (currently 1: k8s-004-mcq-2).

## Required inputs

1. `interview-questions-runner/Interview-Drill-Runner.md` — canonical brief + Appendix A bar
2. `interview-questions-runner/phase2-pilot/pilot.json` — the voice (re-anchor before authoring)
3. `interview-questions-runner/phase4-rewrite/PLAN.md` — execution plan + **operative rubric** (now incl. superlative/comparative + pilot-dupe pre-flight + D_definition mechanism notes)
4. `interview-questions-runner/phase4-rewrite/tracking.json` — state of play (2 batches done, queues, borderline_approved)
5. `interview-questions-runner/phase3-audit/flagged-mcqs.json` — 135 flagged IDs (k8s-014→A, k8s-020→B reclassified)
6. `cloud-labs/lab-095-interview-drill-mcq/questions/interview-{1,2,3}.json` — banks to edit
7. `Interview Prep App/Interview-Prep-Combined.md` (repo root) — source of truth for concepts

## Things to NOT forget

- **Pilot-dupe pre-flight on every batch** (PLAN.md). Five seconds saves an unnecessary reframe.
- **Lead reframes with a recognised actor marker** or the D_definition flag won't clear and drift will FAIL.
- **Operative rubric is settled** — named-identifier fabrications fail categorically; invented-behaviour-of-real-feature (incl. transferred-mental-model identifiers like k8s-004) passes if plausible; superlative framings at-bar only with a factual answer; borderline → surface, don't auto-decide.
- **Match existing bank JSON format** when applying (ensure_ascii=True, indent=2, no trailing newline, CRLF) — keeps the diff to changed `question` lines only.
- **GATE per batch:** surface checkpoint, hold commit until Stephen approves.
- **Helper (committed):** `interview-questions-runner/phase4-rewrite/apply_batch.py` is a generic, reusable batch-apply — `python apply_batch.py <batch.json>` (writes `after` for completed, `before` for dropped; matches bank format).
