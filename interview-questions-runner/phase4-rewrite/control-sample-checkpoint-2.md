# Control sample #2 — GATE 1 re-sample (post LLM pass)

**Date:** 2026-06-02
**Seed:** `SAMPLE_SEED=7919`
**Drawn from:** the 70-MCQ unflagged set (208 − 138 flagged).
**Rubric:** the operative GATE-1 rule (see `PLAN.md` → Tightened rubric → "Operative rule"). Named-identifier fabrications fail categorically; invented-behaviour-of-real-feature passes if a junior could plausibly hold it via transferred mental model; fails on impossibility / false-authority jargon / contradicting basic semantics; borderline → surface.

> **Method note / honest caveat:** the LLM fabrication scan reviewed *every* MCQ in the unflagged set, and the 6 false positives were resolved individually. So this re-sample necessarily draws MCQs that have already been reviewed — it can only *confirm*, not independently probe. The substantive assurance for GATE 1 comes from the exhaustive LLM pass (`llm-fabrication-scan.md`); this sample verifies the flagged/unflagged split is internally consistent with no regression.

## Per-MCQ assessment

### 1. aws-003-mcq-1 — aws — bank 1
Pilot exemplar; resolved heuristic false positive. Distractors invent NACL behaviours ("requires an outbound rule before inbound", "implicitly allows ephemeral return traffic") — invented-behaviour of a real feature, a plausible transfer from Security-Group statefulness. **at-bar.**

### 2. tf-002-mcq-1 — terraform — bank 1
Resolved false positive (literal pilot distractor). Flagged distractor "silently overwrites the first's state" describes a real unlocked-backend hazard — at-bar invented behaviour. **at-bar.**

### 3. git-006-mcq-1 — git — bank 2
Resolved false positive. d2 "Git refuses to push a gitignored-but-tracked file" is an invented constraint a junior genuinely holds (over-attributes enforcement to Git) — structurally identical to the pilot's tf-011 "count cannot shrink". **at-bar.**

### 4. cicd-050-mcq-1 — cicd — bank 2
LLM-pass clean. d1 over-states retry cost (wrong magnitude, not a fabricated billing rule), d2 leans on real fresh-runner behaviour, d3 is a wrong model of when retries run. No named identifier, no impossibility. **at-bar.**

### 5. docker-005-mcq-1 — docker — bank 2
LLM-pass clean. Three naive mental models of real positional layer-cache invalidation (only-referencing-RUNs, everything-for-safety, only-FROM/CMD). **at-bar.**

### 6. k8s-032-mcq-2 — kubernetes — bank 2
LLM-pass clean. d2 "the combination is rejected at apply time" is an invented constraint, but the RoleBinding→ClusterRole type-mismatch intuition is one of the most common RBAC misconceptions — invented-behaviour, plausible transfer. **at-bar.**

## Aggregate

| Verdict | Count | MCQs |
|---|---|---|
| at-bar | 6 / 6 | all |
| borderline | 0 | — |
| fails-rubric | 0 | — |

## GATE 1 result

**6/6 at-bar → GATE 1 CLOSES.** The unflagged set is verified at the pilot bar under the operative rubric. Tier 1 (Task 3, batch T1.1 — AWS D-only stem reframes) may begin in the next session.
