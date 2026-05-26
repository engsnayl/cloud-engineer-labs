# Phase 3 audit — scope of remediation

Produced in response to Stephen's spot-check review of the 18 MCQ sample
that revealed 6/18 met the pilot bar (Appendix A quality). This audit
extrapolates the findings across all 208 MCQs.

## Headline

**126 of 208 MCQs (61%) are flagged for at least one issue.**

That's well past the "~40 MCQs" threshold Stephen named as the signal to
recalibrate the rubric rather than patch case-by-case. **Recommendation:
recalibrate before rewriting.**

## Category breakdown

| Category | Count | Description |
|---|---|---|
| A — Fabricated distractor | 19 | Distractor invents a feature, version, deprecation, billing model, or anti-pattern that isn't a real misconception people hold |
| B — Match-style scrambles | 4 | 2+ distractors are full scrambles in a match/order MCQ, collapsing to elimination-by-format |
| C — NOT/never reversal | 8 | Stem uses "NOT" / "which is not" or correct option is "essentially never" — banned by brief 4.3 |
| D — Definition-style stem | 109 | Stem reads as recall not scenario (7 of these are match-style overlaps) |

Of the 126:
- **29** have structural issues (A, B, or C) that require rewriting the options or stem
- **97** are flagged only for D (recall stem with no scenario context)
- **13** hit multiple categories at once

## What the spot-check revealed and how it maps to 208

Stephen's review of 18 MCQs found 6/18 (33%) met the pilot bar. My audit
across 208 yields 82/208 (39%) without any flag — directionally consistent.
The 67% miss rate is the headline number.

## Root cause analysis

Looking at the patterns of my flagged authoring:

1. **A (fabricated)** correlates with the "third distractor" problem. When
   a real misconception didn't come to mind for the 3rd distractor, I
   invented one — usually phrased authoritatively (specific version,
   percentage, deprecation, billing claim) so it would read as plausible.
   This produces distractors that fail a basic smell test.

2. **B (scrambles)** correlates with match-style MCQs. Once I wrote a
   correct mapping, I generated distractors by permuting it. Two
   permutations + one alternative was a recurring shape — it makes the
   MCQ solvable by spotting non-scrambling rather than by reasoning.

3. **C (NOT/never)** are recurring patterns I drifted into when an MCQ
   tested an absent feature or wrong-by-default behaviour. The brief
   explicitly bans these.

4. **D (definition stems)** is the dominant category and most systemic.
   I tilted toward "What is X?" / "Which fits Y?" framings — easy to
   write, but they test recognition rather than reasoning. The pilot's
   scenarios were the right model; I should have held that bar.

## Recommendation: fresh session for the rewrite

This conversation has produced 208 MCQs, the audit, multiple rebalances,
and the bank merger. **Context budget is significantly used.** I
recommend Stephen kick off a fresh Claude Code session for the rewrite
phase with these inputs:

**Required inputs for the rewrite session:**
- `interview-questions-runner/Interview-Drill-Runner.md` — the brief (canonical rubric, Appendix A samples)
- `interview-questions-runner/phase3-audit/flagged-mcqs.json` — what needs to change
- `cloud-labs/lab-095-interview-drill-mcq/questions/interview-{1,2,3}.json` — the existing 208 MCQs
- `interview-questions-runner/scripts/validate_mcqs.py` — schema + style validator
- `interview-questions-runner/scripts/audit.py` + `audit_suspect.py` — flagging heuristics if you want to verify the audit

**Suggested rubric tightenings before rewriting** (additions to brief 4.2/4.3 that the new session should follow strictly):

- **Distractors must be real misconceptions.** Before writing any distractor, ask "would a real candidate with half-knowledge actually believe this?" If the answer is no, replace it. Do not invent features, versions, deprecations, billing models, CLI flags, or anti-patterns as a way to fill the third slot. Distractor patterns from brief 4.2 should be used; if none of them yields a credible distractor for a given source, the MCQ is wrong.
- **Match-style MCQs may include at most one full scramble.** The other distractors must be partial-correct (gets the relationships almost right, fails on one) or a different framing entirely (e.g., "all of them do the same thing").
- **No "NOT" / "which is not" stems.** No correct option phrased as "essentially never" / "no such thing". These are explicitly banned by brief 4.3.
- **At least 70% of MCQs must have a scenario stem.** Brief 4.4 says "scenario-based where possible". The current 49% is too low. Pure recall stems are acceptable for ~30% of the set when the recall is genuinely the testable point (e.g., octal permissions, port numbers).
- **Single-source coverage:** the two MCQs from one source must test genuinely different facets. Re-check each pair against this bar during the rewrite.

## Files in this directory

- `draft-audit.json` — programmatic heuristic flags (categories C and D)
- `suspect-distractors.json` — distractors matching fabrication-prone patterns (input for manual A review)
- `flagged-mcqs.json` — the final consolidated audit, one row per flagged MCQ
- `README.md` — this file
