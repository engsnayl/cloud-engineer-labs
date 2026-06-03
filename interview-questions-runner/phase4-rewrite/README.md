# Phase 4 — MCQ rewrite

Acts on the 126 flagged MCQs identified in `../phase3-audit/`. Implements
the tiered rewrite-in-place strategy defined in `PLAN.md`.

## Files

- `PLAN.md` — the implementation plan
- `tracking.json` — running counters and per-batch records
- `baseline-snapshot.json` — frozen copy of `../phase3-audit/draft-audit.json`
  from before any rewrite work, used by `../scripts/check_drift.py` to detect
  regressions
- `control-sample.json` / `control-sample-checkpoint.md` — pre-Tier-1 control
- `batch-NN-tierK-slug.json` — per-batch rewrite output
- `batch-NN-checkpoint.md` — per-batch checkpoint surfaced to Stephen
