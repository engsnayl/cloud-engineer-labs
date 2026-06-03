# LLM fabrication scan — 71 unflagged MCQs (GATE 1)

**Date:** 2026-06-02
**Scope:** the 71 MCQs left unflagged after the heuristic expansion (208 − provisional 137). Each of 213 distractors evaluated against the operationalised 6-month-candidate test, hunting four categories: invented **mechanism**, invented **constraint**, invented **config key/field/flag/command** (named identifier), and unverifiable **authoritative causal claim**.
**Method:** 5 domain-sliced agents (AWS×2, K8s, CI/CD, Docker+Git+Linux+TF), each given the pilot bar + the four fabrication templates + explicit false-positive guards, each grepping `Interview Prep App/Interview-Prep-Combined.md` to verify suspect terms. Every `suspect-fabrication` verdict was then re-verified by the reviewer against source/real tooling. Full per-distractor verdicts: `llm-fabrication-scan.json`.

---

## Aggregate

| | MCQs | Distractors flagged |
|---|---|---|
| Clean (all distractors at-bar) | 62 / 71 | — |
| **Tier A — named-identifier fabrications** | 6 | 7 |
| **Tier B — invented-mechanism / claim (contested)** | 3 | 3 |

AWS (29) and Kubernetes (17) came back **100% clean** — every distractor is a real feature in the wrong context, a wrong-value claim about a real field, or a naive mental model. The fabrications cluster in **CI/CD** (5 of 9) and in invented **CLI flags/subcommands** (Docker, Git, Linux, TF — one each).

---

## Tier A — named-identifier fabrications (recommend FLAG regardless of bar)

These invent a **specific name that does not exist** — a config key, CLI command, flag, or naming convention. A candidate cannot reach these from a misconception; they only "believe" them by falsely thinking they saw them in docs. This is the same class as the control sample's hard fail `skip-matrix:`.

| MCQ | Distractor | Invented identifier |
|---|---|---|
| cicd-011-mcq-2 | d3 | `COMPOSITE_`-prefixed secret naming convention |
| cicd-022-mcq-1 | d3 | `aws ecs deploy-now` CLI command + "queued deploy" state |
| docker-004-mcq-2 | d2 | `docker build --no-context` flag |
| git-003-mcq-2 | d2 | `git pull --fork` flag |
| linux-006-mcq-2 | d1, d3 | journalctl `--severity`/`--realtime` flags; `systemctl follow` subcommand |
| tf-010-mcq-2 | d3 | `--ami-from-packer` flag |

**Note on agent reliability:** the Docker/Git/Linux/TF agent initially rated all four invented flags **at-bar**, justifying it by citing pilot distractors `aws ecr push`, `--persist=true`, `helm secrets` as accepted-invented-flag precedent. **Those examples do not exist in `pilot.json`** — the agent hallucinated the precedent. The real pilot never accepts an invented *named identifier*; its invented distractors are all *behaviors* (see below). The reviewer therefore revised these four MCQs from clean → has-suspect. This is exactly the systematic-error risk the dispatch pattern warns about, caught by the reviewer-verify step.

---

## Tier B — invented mechanism / claim (CONTESTED — depends on where the bar sits)

These invent a **behavior** of a real feature, not a name. Each maps to a believable naive mental model:

| MCQ | Distractor | Invented behavior | Naive model it encodes |
|---|---|---|---|
| cicd-012-mcq-1 | d1 | a GHA "matrix coordinator" job that aggregates results | "something must collect the matrix results" |
| cicd-013-mcq-1 | d3 | an action-version-keyed shared cache pool across all workflows | "the `@v4` is the cache key" (sibling of its d1/d2) |
| cicd-022-mcq-2 | d1 | `minimumHealthyPercent=200` → double capacity + one-cut switch | a real field (surge is actually `maximumPercent`) given an invented effect |

**These are at-bar under the project's own pilot standard, and only fabrications under the strict control-sample reading.** See the contradiction below.

---

## The calibration contradiction the user must resolve

`pilot.json` — the canonical at-bar bar — **contains the very pattern Tier B (and the heuristic "constraint"/"mechanism" expansion) treats as fabrication:**

- **`tf-011-mcq-1`** is *in the pilot* as an at-bar exemplar. Its distractor_2 is *"Terraform refuses to apply because count cannot shrink … without a terraform state mv first"*, and the pilot explanation **endorses it**: *"invents a count-can't-shrink constraint that doesn't exist … natural-sounding, but count doesn't behave that way."* Yet the **control sample flagged this exact distractor as a (mild) fabrication**, and the **heuristic expansion flagged the same MCQ** (`constraint-refuses`). The pilot and the audit now disagree about the same MCQ.
- **`aws-003-mcq-1`** (pilot): d3 *"AWS implicitly allows ephemeral-port return traffic"* — explanation: *"invents an implicit-allow that doesn't exist."* At-bar in the pilot.
- **`tf-002-mcq-2`** (pilot): d2 *"hashed … using an envelope key derived from the DynamoDB state lock"* — explanation: *"invents a hashing scheme tied to DynamoDB that doesn't exist."* At-bar in the pilot.

So the pilot's working definition of a *good* distractor explicitly includes "invents a natural-sounding behavior/constraint of a real feature that doesn't actually exist." That is precisely Tier B. The control sample applied a stricter reading and called the same shape a fabrication.

**Synthesis the reviewer recommends:** the real axis isn't "invented vs not" — it's **naive-misconception vs false-authority**.
- *Naive misconception* (at-bar): a wrong model a junior would genuinely hold — "pods self-coordinate", "count can't shrink", "matrix coordinator job". Low specificity, reasoned-into.
- *False authority / named identifier* (fabrication): reads like expert doc-knowledge a candidate can't derive or verify — the control sample's docker "kernel buffer the daemon doesn't drain", and every Tier A named identifier.

Under this synthesis: **Tier A flags; Tier B stays at-bar; and the control sample's two borderline-fails (`tf-011-mcq-1`, `git-006-mcq-1` "Git refuses to push…") were false positives**, consistent with `tf-011-mcq-1` being a pilot exemplar.

---

## False-positive resolutions (the 4 carried from the heuristic expansion)

| FP | Resolution |
|---|---|
| `key-not-in-allowlist:python` / `:ubuntu` (docker-004-mcq-1) | FP — image tags, not keys. MCQ stays flagged on its own `D_definition`. Add image-tag allowlist. |
| `key-not-in-allowlist:aws` (cicd-020-mcq-2) | Key is a FP (`aws:MultiFactorAuthPresent` is real); MCQ stays flagged on its own `A_fabricated`. JWT-MFA-inheritance claim verified as a real misconception (pilot cicd-020-mcq-1 treats it as at-bar) — no fab. |
| `mechanism-silent-failure` (tf-002-mcq-1) | FP — literal pilot distractor. **Removes tf-002-mcq-1 from the 11** → expanded flagged 137 → 136. No LLM review needed. |
| (consequential) `tf-011-mcq-1` constraint flags | **Under the recommended synthesis, also a FP** — it is a pilot exemplar. Would drop expanded flagged further and is a control-sample false positive. |

---

## What gets folded into the flagged set — by decision

- **If bar = named-identifier only (recommended):** add the **6 Tier A MCQs**; Tier B stays at-bar; resolve `tf-011-mcq-1` (and by extension `git-006-mcq-1`) as control-sample false positives.
- **If bar = strict (any invented mechanism/constraint):** add **all 9** (Tier A + Tier B) — **and the pilot itself is off-bar** (`tf-011-mcq-1`, `aws-003-mcq-1`, `tf-002-mcq-2` would need rework), which reopens Phase 2.

---

## Re-baseline + re-sample plan (after the bar is set)

1. Fold the agreed fabrications into `phase3-audit/flagged-mcqs.json` with `A_fabricated`-style flags + notes; resolve the 4 (or 5) FPs.
2. Refresh `tracking.json` (new `expanded_total_flagged`, FP resolutions, `llm_pass_pending: false`); refine `audit_suspect.py` allowlist (image tags, real IAM keys, pilot-distractor exemption) so the heuristic stops re-tripping.
3. Re-run `sample_unflagged.py` with `SAMPLE_SEED=7919` against the new flagged set → 6 fresh control MCQs → `control-sample-checkpoint-2.md`.
4. **GATE 1 closes only if the re-sample clears the bar** (target 6/6 strict, or ≥4/6 with documented spot-check). Tier 1 stays on hold until then.
