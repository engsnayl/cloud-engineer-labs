# Phase 4 — final report (MCQ bank rewrite)

**Branch:** `feat/lab-interview-drill-phase1` · **Phase-4 HEAD:** `9c9ad52` (Tier 3 close) · **Date:** 2026-06-03

## Headline

- **135 originally-flagged MCQs → 0 residual structural flags.**
- **Bank unchanged at 208 MCQs (70 / 69 / 69); 0 items cut** — all 6 Tier-1 dropouts were reauthored in Tier 3, and Tier 3 had 0 dropouts.
- Re-audit from clean state: **3 MCQs carry a heuristic flag — all 3 are pilot exemplars** (the bar itself), byte-identical to `pilot.json` and flagged identically in `baseline-snapshot.json`. Not defects, not regressions.
- `validate_mcqs.py`: **OK on all three banks (0 errors).**

## Tiered work

| Tier | Scope | Outcome |
|---|---|---|
| **Tier 1** (T1.1–T1.5) | Stem reframes (D-class) | **86 reframes** / 92 attempted; 6 routed to Tier 3 (dropout 6.52%); +1 pilot-FP cleared (aws-026), 1 micro-edit (aws-009-mcq-2), 1 borderline-approved (k8s-004-mcq-2) |
| **Tier 2** (T2.1) | A-only fabricated distractor swaps | **23 swap items / 30 distractors swapped**; +1 verify-no-change FP (cicd-031-mcq-1); +1 deferred to Tier 3 (aws-022) |
| **Tier 3** (T3.1, T3.2) | Full reauthors (structural / compare / superlative / multi-flag) + 1 option-balance | **28 items** (27 reauthors + 1 option-balance); **0 dropouts**; 8 suspect-heuristic FPs recorded |

Flag-class resolution (149 flag instances across the 135 items): D_definition 98 (Tier-1 reframes + Tier-3 reauthors) · A_fabricated 32 (Tier-2 swaps + Tier-3 reauthors) · D_match_style 7 (Tier-3 match→scenario) · C_never_correct 6 (Tier-3 positive reframes) · B_scrambles 4 (Tier-3) · C_not_reversal 1 (Tier-3) · B_structural_option_balance 1 (Tier-3 k8s-020).

## Re-audit from clean state (Task 11 Step 1)

```
audit.py        : 208 MCQs — stem types {scenario: 206, definition: 2};
                  MCQs with any C/D flag: 3  (aws-026-mcq-1, cicd-020-mcq-1, k8s-010-mcq-1)
audit_suspect.py: 62 distinct MCQs match fabrication-PRONE patterns (manual-review net;
                  reviewed — residuals are real misconceptions / recorded FPs, not fabrications)
validate_mcqs.py: OK / OK / OK (banks 1/2/3, 0 errors)
```

Bank sizes and domain mix are unchanged from Phase-4 start (no items added or cut): aws 56 · kubernetes 44 · cicd 36 · terraform 26 · docker 20 · linux 14 · git 12.

## The 3 residual-flagged MCQs — known/expected (pilot exemplars)

These are the pilot exemplars themselves, flagged by the heuristic's known limitations; they define the bar and are byte-identical to `pilot.json` (auto-clear rule applies). Flags match `baseline-snapshot.json`, so they are not regressions.

| MCQ | Heuristic flag | Why it's a false positive |
|---|---|---|
| `aws-026-mcq-1` | D_definition | Genuine scenario stem that leads with an unrecognised noun ("A Python service…"), which the stem classifier doesn't match |
| `k8s-010-mcq-1` | D_definition | Same — leads with "A backend microservice…" |
| `cicd-020-mcq-1` | C_never_correct | Correct option legitimately begins "No long-lived credential is stored…"; the C-check trips on the leading "No" |

## False-positive ledger (all recorded with rationale)

- **3 pilot-exemplar FPs** — the three above; heuristic limitation, at-bar by definition.
- **1 Tier-2 verify-no-change** — `cicd-031-mcq-1` / d2 ("column rename is a metadata-only, no-downtime ALTER TABLE"): reviewed as a genuine junior misconception, not a fabrication → kept unchanged.
- **8 Tier-3 suspect FPs** — all real misconceptions matching a fabrication-prone *pattern*, no named-identifier fabrication:
  - T3.1 (3, `auto-implicit`): `cicd-001-mcq-1/d3` (scheduled-nightly ≡ CD), `k8s-001-mcq-2/d2` (bare RS won't self-heal), `aws-005-mcq-2/d2` (Multi-AZ auto-routes reads).
  - T3.2 (5): `git-003-mcq-1/d3` (`--force` bypasses a permission denial; `specific-flag`), `tf-004-mcq-1/d2` + `docker-002-mcq-2/d2` + `docker-003-mcq-2/d1` (`auto-implicit`), `tf-005-mcq-1/d1` (workspaces "can't be selected non-interactively"; `constraint-cannot-without`).

**Standing rule:** any distractor matching a suspect pattern (notably "automatically") gets the misconception-vs-fabrication check; pass → record FP, keep.

## Length-tell (correct-is-longest) — measured, decision documented

`correct-is-longest` = correct option is the longest of the four. `trips` = correct exceeds every distractor by >1.25× **and** by >20 chars (the validator's giveaway threshold — the only length signal a test-taker can exploit).

| Cohort | correct-is-longest | trips (giveaway) |
|---|---|---|
| **Tier-3 reauthored** (options fully ours) | 92.9% (26/28) | **0** |
| Tier-2 swapped (1 distractor ours) | 29.2% (7/24) | 1 |
| Tier-1 stem-only (options untouched) | 53.6% (45/84) | 13 |
| Untouched originals | 45.8% (33/72) | 5 |
| **Whole bank** | 53.4% (111/208) | 19 |

**Decision (Stephen, 2026-06-03): accept the Tier-3 soft residual; no parity pass.**

- The **integrity bar is the giveaway threshold (`trips`), and Tier-3 is the cleanest cohort in the bank at 0** — every trip introduced during authoring was cleared by lengthening a distractor to carry its own wrong mechanism (the correct option is never shortened, per the MCQ-reasoning rule that the correct answer states the load-bearing mechanism).
- The 92.9% soft "correct-is-longest" is the **accepted cost of correct-carries-mechanism**: with 0 trips, "longest" means *marginally* longest (within 1.25×), which is not a reliably exploitable signal.
- The 18 `trips` outside Tier-3 are **pre-existing original-author tells** in options Phase 4 never rewrote (Tier-1 touched stems only). They are out of scope for this phase and left as-is.

## PR readiness

- All Phase-4 commits are on `origin/feat/lab-interview-drill-phase1` (Tier 1 + Tier 2 + Tier 3 + housekeeping).
- Banks validate clean; drift PASS on every batch; reconciliation clean (135 → 0 residual).
- Derived artifacts are excluded from the diff: `suspect-distractors.json` is gitignored; `draft-audit.json` is regenerated by the audit suite and intentionally never staged.
- **Status: ready for PR review. The PR is NOT opened or merged — held for Stephen's go.**
