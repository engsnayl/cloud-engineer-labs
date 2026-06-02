# Phase 4 — handoff (2026-06-02)

## Current state

- **Plan:** approved with 4 review additions; committed as `edba19b`. See `PLAN.md`.
- **Task 0 (drift script):** done. `scripts/check_drift.py` mechanises the audit drift check; smoke-tested PASS against the real baseline. Committed as `f3f8f57`.
- **Task 1 (scaffold + baseline):** done. `phase4-rewrite/` directory created; `baseline-snapshot.json` is a frozen copy of `phase3-audit/draft-audit.json` (audit.py detects 115 of the 126 flagged MCQs mechanically). Committed as `9d32fce`.
- **Task 2 (control sample):** **GATE 1 failed.** 6 unflagged MCQs sampled; 2 clear fabrications (`cicd-012-mcq-2` invented YAML key `skip-matrix:`, `docker-010-mcq-2` invented kernel-buffer mechanism) + 2 borderline-treated-as-fail (`git-006-mcq-1`, `tf-011-mcq-1`). Strict at-bar rate 2/6 trips STOP threshold. See `control-sample-checkpoint.md`.
- **Decision:** expand audit scope before any Tier 1 work. Both heuristic pattern additions AND an LLM pass, in that order.
- **Pattern additions:** **done this session.** `scripts/audit_suspect.py` now has three new pattern groups (mechanism-claim, invented-constraint, invented-key with allowlist). All 4 control-sample failures are caught by the new patterns. Expanded flagged total: **126 → 137** (11 new flagged MCQs from the pattern expansion).
- **LLM pass:** **PENDING** — explicit next-session work.

## Files touched in this session

| Path | Status |
|---|---|
| `interview-questions-runner/phase4-rewrite/PLAN.md` | Created and committed; revised with 4 additions; revised again to relax pre-flight path |
| `interview-questions-runner/phase4-rewrite/README.md` | Created |
| `interview-questions-runner/phase4-rewrite/tracking.json` | Created and progressively updated |
| `interview-questions-runner/phase4-rewrite/baseline-snapshot.json` | Frozen baseline (208 rows; 115 flagged by audit.py mechanically) |
| `interview-questions-runner/phase4-rewrite/control-sample.json` | 6 sampled unflagged MCQs (seed=4096) |
| `interview-questions-runner/phase4-rewrite/control-sample-checkpoint.md` | Per-MCQ rubric assessment |
| `interview-questions-runner/phase4-rewrite/HANDOFF.md` | This file |
| `interview-questions-runner/scripts/check_drift.py` | New — drift-check script |
| `interview-questions-runner/scripts/sample_unflagged.py` | New — control-sample picker |
| `interview-questions-runner/scripts/audit_suspect.py` | Extended with 3 new pattern groups + allowlist + breakdown reporting |
| `interview-questions-runner/phase3-audit/suspect-distractors.json` | Regenerated (95 entries, 73 distinct MCQs) |
| `interview-questions-runner/phase3-audit/draft-audit.json` | Refreshed (idempotent on no-bank-change) |

## Exact next action for the new session

**Task: LLM-based fabrication scan over the 82 unflagged MCQs (minus those now caught by expanded heuristics).**

The expansion caught **11 new** MCQs the audit was missing, but the LLM pass is needed for the long tail — fabrications that don't match any heuristic pattern. Look for:

1. **Invented mechanisms** that read as plausible technical jargon but describe non-existent layer-internal behaviour. The `docker-010-mcq-2` case is the template ("kernel buffer that the daemon doesn't drain").
2. **Invented constraints** that read as plausible tool rules. The `tf-011-mcq-1` distractor_2 ("count cannot shrink without state mv first") and `git-006-mcq-1` distractor_2 ("Git refuses to push... until you delete it from disk") are the templates.
3. **Invented config keys / fields / flags / annotations** that don't appear in official docs for the relevant tool. The `cicd-012-mcq-2` case (`skip-matrix:`) is the template — the allowlist catches the obvious ones; the LLM pass catches keys that read like real ones (think `nodeAffinity-strict: true`, `--retry-on-throttle`, etc.) that fall outside the allowlist's coverage.
4. **Authoritative-sounding causal claims** that a 6-month candidate could not verify in 5 minutes of doc-reading.

**Mechanics:**

- Source: `cloud-labs/lab-095-interview-drill-mcq/questions/interview-{1,2,3}.json`
- Filter to MCQs whose IDs are NOT in the expanded flagged set (after merging the original 126 + the 11 new from heuristic expansion = 137). The remaining ~71 MCQs are the LLM-pass target.
- For each remaining MCQ, evaluate the 3 distractors against the 6-month-candidate test (see `PLAN.md` "Tightened rubric" section).
- Emit a structured report: per-MCQ, per-distractor verdict + one-sentence justification + suspected fabrication category if any.
- After the LLM pass, finalise `phase3-audit/flagged-mcqs.json` to include all MCQs flagged by (a) the original audit + manual review (126), (b) the heuristic expansion (+11), (c) the LLM pass (TBD).
- Update `tracking.json` with the final expanded count, then GATE 1 is closed and Tier 1 may begin.

## Required inputs for the new session

1. `interview-questions-runner/Interview-Drill-Runner.md` — canonical brief and Appendix A samples
2. `interview-questions-runner/phase2-pilot/pilot.json` — 10 pilot MCQs at the bar (re-anchor before evaluating)
3. `interview-questions-runner/phase3-audit/flagged-mcqs.json` — current 126-flagged consolidated list
4. `interview-questions-runner/phase3-audit/suspect-distractors.json` — post-expansion suspect output (95 entries)
5. `interview-questions-runner/phase4-rewrite/PLAN.md` — the implementation plan
6. `interview-questions-runner/phase4-rewrite/tracking.json` — state of play, including the false-positives noted to triage
7. `interview-questions-runner/phase4-rewrite/control-sample-checkpoint.md` — what the operationalised 6-month-candidate test looks like in practice
8. `interview-questions-runner/phase4-rewrite/HANDOFF.md` — this file
9. `cloud-labs/lab-095-interview-drill-mcq/questions/interview-{1,2,3}.json` — the 208 MCQ banks
10. `~/interview-prep-app/Interview-Prep-Combined.md` OR `Interview Prep App/Interview-Prep-Combined.md` (repo root) — source material for ground-truth concept checks

## Things to NOT forget in the next session

- **Resolve the 4 known false-positives** listed in `tracking.json` under `audit_expansion.known_false_positives_to_review_next_session` before counting them against MCQ authors.
- **The 4 control-sample failures** (`cicd-012-mcq-2`, `docker-010-mcq-2`, `git-006-mcq-1`, `tf-011-mcq-1`) are already in `fails_rubric_pending_re_audit`. Do NOT fold them into a Tier 2 batch piecemeal — they go into the single expanded Tier 2 batch alongside whatever else the LLM pass surfaces.
- **Re-run the control sample with a different seed** (e.g. `SAMPLE_SEED=7919`) after the LLM pass closes; only then is GATE 1 truly cleared.
- **Tier 1 still has not started.** All work to date has been audit-and-scaffold. The first actual MCQ rewrite happens after GATE 1 closes.
