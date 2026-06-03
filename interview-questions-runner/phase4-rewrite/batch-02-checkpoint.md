# Batch T1.2 checkpoint

**Tier:** 1  **Slice:** Kubernetes D-only  **Date:** 2026-06-02

## Audit script result on batch

- **Drift check: PASS** — `touched_count: 17`, `touched_still_flagged: []`, `regressions: []`.
- New audit re-flags on touched IDs: none.
- Validate script: **PASS** on all three banks (exit 0); only pre-existing soft length warnings, none on a stem this batch touched.
- Diff vs HEAD: **17 insertions / 17 deletions** — one `question` line per MCQ, nothing else (options/explanations untouched).

## Session context status

- Estimated context usage: **~60% (50–65% band)**.
- Handoff recommended: **YES** — start a fresh Claude Code session before T1.3 (CI/CD). Resume from this checkpoint's `tracking.json` state. Two full batches (34 MCQs authored) plus the FP-class work this session; per execution discipline rule 7, banking T1.2 and re-anchoring fresh will keep T1.3 authoring quality up.
- Notes: T1.1 + T1.2 done this session. Pilot re-read end-to-end at the start of each tier.

## Self-assessment numbers

- Slice total: **17** (was 18; `k8s-010-mcq-1` already cleared as a pilot FP in T1.1)
- Pilot-duplicate pre-flight: **0** byte-identical-to-pilot in slice
- Reframe-attempted: **17**
- MCQs completed at tier: **17** (all pure Tier-1 stem reframes)
- Dropouts to Tier 3: **0**
- Fabrications caught at self-review: **0** (but 2 borderline distractor calls surfaced below)
- Distractor swaps applied: **0** (Tier 1 does not author distractors)
- Distractor self-check records written: **51** (17 × 3)
- **Cumulative Tier 1 dropout rate: 3.03%** (1 of 33 reframe-attempts; vs 20–30% estimate)

### Honesty note on the low dropout rate (still holding)

Same mechanism as T1.1: D-only means the stem lacked a recognized scenario-actor marker; the concepts and options were already sound, so adding a concrete actor disturbs nothing. No reframe forced an option/explanation change → 0 genuine drops. I did **not** suppress drops — where I saw real problems (below), they're distractor-quality issues orthogonal to the stem reframe, so they're surfaced for Tier 2, not hidden as "completed."

## Borderline calls surfaced for your decision (not auto-decided)

### 1. k8s-004-mcq-2 — invented K8s API field names in distractors
Distractors propose a `sidecarContainers:` field, a `containerType: sidecar` field, and a `kubernetes.io/sidecar` annotation — none real (native sidecars are init containers with `restartPolicy: Always`). This is named-identifier territory, which the operative rubric says fails categorically. **My recommendation: at-bar, keep.** For a "how is this declared?" question, a 6-month candidate genuinely guessing `sidecarContainers:` is a natural wrong guess, not a "saw-it-in-docs" fabrication — and a declaration question needs plausible-but-wrong syntax as distractors. But it's close enough to the rule that I'm flagging it; if you'd rather apply the strict read, it goes to Tier 2 for a distractor swap.

### 2. k8s-014-mcq-1 — fabricated number + comparison framing
- **distractor_2** invents a "32 entries per pod" env-var limit. A specific fabricated number leans **fail** under the named-identifier rule. **Recommendation: send distractor_2 to Tier 2 for a swap** (replace with a real env-var-discovery misconception); the other three options are fine.
- **Framing:** the stem asks "why is env-var discovery the *weaker* option." I weighed this against your aws-021 "worst candidate" ruling and judged it **structurally distinct** — it's a two-option comparison with a *factual* correct answer (env vars are snapshotted at pod start) and wrong-*reason* distractors, not "pick the failing item from a list of good ones." I reframed with an actor and kept the comparison. If you read it as the same problem, it drops to Tier 3 instead.

### 3. k8s-020-mcq-1 — length tell (structural, pre-existing)
`correct` is one word ("StatefulSet") while all three distractors are full sentences — guessable by length. Not a Tier-1 fix (options untouched); flagging for a Tier-3 option-balance pass.

## Sample MCQs from this batch

### k8s-013-mcq-1 — Tier 1 — least confident: no
**Before stem:** Within a Kubernetes cluster, what's the fully-qualified DNS name pattern for a Service?
**After stem:** A pod in one namespace needs to reach a Service in another namespace using its fully-qualified DNS name. Which name pattern is correct?
**Options (after — unchanged):** correct = `<service>.<namespace>.svc.cluster.local`; distractors = segment-order swap, invented `k8s.local` domain, `-` namespace separator.
**Note:** genuine recall (DNS pattern) wrapped in a real cross-namespace scenario that tests application; rubric permits recall here, but the scenario is legitimate, not thin.

### k8s-041-mcq-1 — Tier 1 — least confident: no
**Before stem:** What is IRSA in EKS, in one sentence?
**After stem:** A pod on EKS needs AWS credentials without any long-lived keys, and a teammate suggests using IRSA. What is IRSA?
**Options (after — unchanged):** correct = IAM Roles for Service Accounts (OIDC token → AssumeRoleWithWebIdentity); distractors = wrong acronym expansions (Instance Role / Inter-Region / Internal Replicated Service Account).
**6-month justification:** d1 ("Instance Role Service Account") describes the node-role anti-pattern IRSA replaced — very believable; d2/d3 are plausible acronym guesses.

### k8s-004-mcq-2 — Tier 1 — least confident: YES
**Before stem:** Kubernetes 1.28 introduced native sidecar containers. How are they declared and how do they differ from regular main containers?
**After stem:** An engineer on Kubernetes 1.28 wants to add a native sidecar container to a pod. How is it declared, and how does it differ from a regular main container?
**Why least confident:** the invented-field-name distractors (see borderline #1). Stem reframe is clean; the distractor judgment is the open question.

### k8s-014-mcq-1 — Tier 1 — least confident: YES
**Before stem:** Why is environment-variable-based service discovery in Kubernetes considered worse than DNS-based discovery?
**After stem:** An engineer is choosing between environment-variable and DNS-based service discovery in Kubernetes and asks why the env-var mechanism is the weaker option. What's the main reason?
**Why least confident:** distractor_2's fabricated "32 entries" limit + the comparison-framing question (see borderline #2).

## Decision — RESOLVED (Stephen, 2026-06-02)

1. **17 reframes — APPROVED** (drift PASS, validate PASS).
2. **k8s-004-mcq-2 — AT-BAR**, kept. Invented field names are transferred-mental-model (Kubernetes does name things this way). Recorded in `tracking.json → borderline_approved`; revisit the bar if Tier 1 yields 3+ such cases.
3. **k8s-014-mcq-1 — SPLIT.** d2 "32 entries per pod" = fabrication → queued for **Tier 2** (widens T2.1; flagged-mcqs.json reclassified D→A). "Weaker than" framing **kept** — rubric distinction recorded in PLAN.md (superlative/comparative is at-bar when the property has a factual answer; not when it reduces to "pick the failing option").
4. **k8s-020-mcq-1 — Tier-3 option-balance pass** → queued for **T3.2** (stem stays reframed; flagged-mcqs.json reclassified D→B_structural_option_balance).
5. **Handoff CONFIRMED** — fresh session for T1.3.

Committed as batch T1.2.
