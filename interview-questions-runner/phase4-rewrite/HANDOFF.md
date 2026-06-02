# Phase 4 — handoff (2026-06-02, GATE 1 closed)

## Headline state

- **Total flagged: 138 / 208** (`phase3-audit/flagged-mcqs.json`, 138 entries).
- **GATE 1: CLOSED.** Seed-7919 control sample = 6/6 at-bar under the operative rubric.
- **Next action: Tier 1 begins — Task 3, batch T1.1 (17 AWS D-only stem reframes).** See `PLAN.md` Task 3. No Tier 1 work has started yet.

## What happened this session (GATE 1 closure)

1. **LLM fabrication scan** over the 71 unflagged-after-expansion MCQs (5 domain-sliced agents + reviewer verification of every suspect against `Interview Prep App/Interview-Prep-Combined.md` and real tooling). Deliverables: `llm-fabrication-scan.json` (per-distractor verdicts) + `llm-fabrication-scan.md` (summary). Result: 62/71 clean, 9 fabrications.
2. **Operative rubric settled** (recorded in `PLAN.md` → Tightened rubric → "Operative rule"): the 6-month-candidate test is the bar — *named-identifier* fabrications (invented keys/commands/flags/specific-numbers/deprecations) fail categorically; *invented-behaviour-of-a-real-feature* passes if a junior could plausibly hold it via a transferred mental model, fails on impossibility / false-authority jargon / contradicting basic semantics; borderline → surface (reference borderline: `k8s-014-mcq-2`). The pilot stands unchanged.
3. **Rebaseline 126 → 138.** Added 12 net-new `A_fabricated` MCQs:
   - LLM pass (7): `cicd-011-mcq-2`, `cicd-022-mcq-1`, `docker-004-mcq-2`, `git-003-mcq-2`, `linux-006-mcq-2`, `tf-010-mcq-2`, `cicd-022-mcq-2`
   - control-sample confirmed (2): `cicd-012-mcq-2`, `docker-010-mcq-2`
   - heuristic-adds adjudicated (3): `aws-019-mcq-2`, `cicd-021-mcq-1`, `tf-003-mcq-2`
4. **6 heuristic false-positives resolved** (not flagged): `aws-003-mcq-1`, `tf-002-mcq-1`, `tf-011-mcq-1` (pilot exemplars), `git-006-mcq-1`, `k8s-021-mcq-1` (stem-defined label), `k8s-014-mcq-2` (borderline, at-bar). `docker-004-mcq-1` and `cicd-020-mcq-2` stay flagged on their independent D/A flags (only their bad suspect-key tags cleared).
5. **Re-sample (seed 7919) = 6/6 at-bar** → GATE 1 closed. See `control-sample-checkpoint-2.md`. Caveat: the LLM pass covered the whole unflagged set, so the sample confirms rather than independently probes.

## Commits this session (on `feat/lab-interview-drill-phase1`)

- `dd56495` LLM scan deliverables + rebaseline flagged 126→138
- `5997fbe` operative fabrication rubric in PLAN.md
- `8e52f88` tracking.json final disposition
- `0d824e4` GATE 1 closed — seed-7919 control sample 6/6 at-bar
- `b5d755c` HANDOFF for Tier 1 (this file)
- (plus a follow-up commit correcting this list)

## Exact next action for the new session

**Task 3 — batch T1.1: reframe the 17 AWS D-only MCQ stems to scenario form.** Follow `PLAN.md` Task 3 step-by-step. In brief:

- Step 0: re-anchor on `phase2-pilot/pilot.json` (the voice).
- Step 1: identify the 17 AWS D-only IDs — `python -c "import json; d=json.load(open('interview-questions-runner/phase3-audit/flagged-mcqs.json')); ids=[x['id'] for x in d if x['flags']==['D_definition'] and x['domain']=='aws']; print(len(ids)); [print(i) for i in ids]"`
- Steps 2–4: Tier 1 procedure (stem reframe only; drop to Tier 3 if a reframe forces option/explanation changes), write `batch-01-tier1-aws.json`, apply back into the bank files.
- Step 5: `validate_mcqs.py` on all three banks.
- Step 6: `check_drift.py batch-01-tier1-aws.json` — must PASS (drift FAIL → checkpoint shows only the drift, fix locally first).
- Steps 7–10: update `tracking.json`, write `batch-01-checkpoint.md`, surface to Stephen (GATE), commit.

## Required inputs for the new session

1. `interview-questions-runner/Interview-Drill-Runner.md` — canonical brief + Appendix A bar
2. `interview-questions-runner/phase2-pilot/pilot.json` — the voice (re-anchor before authoring)
3. `interview-questions-runner/phase4-rewrite/PLAN.md` — execution plan + **operative rubric**
4. `interview-questions-runner/phase4-rewrite/tracking.json` — state of play (138 flagged, GATE 1 closed)
5. `interview-questions-runner/phase3-audit/flagged-mcqs.json` — the 138 flagged IDs with flags/notes
6. `cloud-labs/lab-095-interview-drill-mcq/questions/interview-{1,2,3}.json` — the banks to edit
7. `Interview Prep App/Interview-Prep-Combined.md` (repo root) — source of truth for concepts

## Things to NOT forget

- **The operative rubric is settled** — apply it to every distractor touched in Tier 1/2/3. Borderline → surface, don't auto-decide (`k8s-014-mcq-2` is the reference case).
- **The `audit_suspect.py` constraint/mechanism/key heuristics over-flag** invented-behaviour distractors (incl. pilot exemplars). Treat their output as a contrast signal, not a verdict. Allowlist refinements are listed in `tracking.json` → `audit_expansion.allowlist_refinements_todo` (image tags, real IAM keys, real k8s fields, pilot-distractor text) — optional cleanup, not blocking.
- **`final-report.md` (Task 11) must document the audit-expansion honesty**: the expansion was overreaching but useful (caught the 6 named-identifier cases, gave a contrast set for the judgment calls).
- **Tier slicing is locked** (PLAN.md). The new fabrications surfaced this session (the 12) are `A_fabricated`-type and belong to **Tier 2** (distractor swaps), not Tier 1 — Tier 1 is D-only stem reframes. Tier 2 batch T2.1 will need to widen beyond the original 11 A-only MCQs to absorb these; reconcile the Tier 2 slice count when you reach Task 8.
