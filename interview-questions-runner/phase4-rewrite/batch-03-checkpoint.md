# Batch T1.3 checkpoint

**Tier:** 1  **Slice:** CI/CD (cicd) D-only  **Date:** 2026-06-02

## Audit script result on batch

- Drift check: **PASS** — `{touched_count: 16, touched_still_flagged: [], regressions: [], result: "PASS"}`
- New audit re-flags on touched IDs: none
- Validate script: **PASS** (interview-1/2/3.json all exit 0; only pre-existing option-length soft warnings, none introduced by this batch)
- Pilot-dupe pre-flight: 0 byte-identical-to-pilot in slice
- Pre-apply `classify_stem()` check: all 16 reframed stems classify as `scenario`, none trip the NOT/never C-flag

## Session context status

- Estimated context usage: under 50% (~15–20%)
- Handoff recommended: no — comfortable margin to continue to T1.4 this session if approved
- Notes: previous batches in this session: 0 (fresh session resumed from HANDOFF); T1.1 + T1.2 already committed upstream

## Self-assessment numbers

- MCQs attempted (reframe-attempts): 16
- MCQs completed at tier: **15** (all pure Tier-1 stem-only reframes)
- Dropouts to Tier 3: **1** (cicd-001-mcq-1)
- Fabrications caught at self-review (rejected before commit): 0 (no distractors touched — stem-only)
- Distractor swaps applied: 0
- Tier-1.5 micro-edits: 0
- Running Tier 1 dropout rate after this batch: **4.08%** (2 of 49 reframe-attempts across T1.1–T1.3; T1.1: 1, T1.2: 0, T1.3: 1) — well under the 20–30% estimate

**Disposition (Stephen, 2026-06-02):** 15 of 16 approved as Tier-1 reframes; **cicd-001-mcq-1 dropped to Tier 3**. For the 15 applied, options and explanation are byte-identical before↔after (asserted in the generator and re-asserted at apply); D-only flags mark a missing scenario-actor marker, not a content defect, so leading each stem with a recognised actor disturbs nothing.

**Why cicd-001-mcq-1 went to Tier 3 (not Tier 1):** the question form is definitional-distinction ("distinguish CD from CDep"), answered purely on recall. The added scenario and teammate-mislabel are inert (Chekhov's gun) — the four options are abstract definition-pairs that no stem edit can make scenario-dependent, so the applied setup never pays off. Making it applied requires rewriting the options into scenario-classifications = option rewrite = Tier 3. A mechanism-only stem reword does NOT fix it; the inertness is in the options, not the stem. Bank stem reverted to original; queued for Tier-3 absorption.

## Sample MCQs from this batch

### cicd-014-mcq-2 — Tier 1 — least confident: no

**Before stem:** A production deploy job needs a manual approval and access to prod-only secrets. Which GitHub Actions feature delivers both?
**After stem:** Your team's production deploy job needs a manual approval before it runs, plus access to prod-only secrets. Which GitHub Actions feature delivers both?

**Options (after):**
- correct: Environment with required reviewers — the job pauses for the named reviewer's approval, and the environment's secrets become available only after approval
- distractor_1: Branch protection rules — required reviewers on the protected branch act as the deploy approval and unlock the secret store
- distractor_2: Workflow concurrency groups — by setting concurrency on the deploy workflow, the second pending run waits for human approval to proceed
- distractor_3: Repository ruleset 'production' — when a workflow runs against a tag matching the ruleset, secrets become available conditionally

**6-month-candidate justification for any touched distractor:** none touched. (Original stem already had a scenario but led with "A production deploy job" — "production" is not in the audit's recognised-actor allowlist, so it fell through to D. The reframe just re-leads with "Your team's …".)

### cicd-031-mcq-2 — Tier 1 — least confident: no

**Before stem:** During an expand-contract migration, why is the backfill step often the longest and most fragile?
**After stem:** Your team is running an expand-contract migration on a large production table, and the backfill step keeps dragging on and causing incidents. Why is the backfill step often the longest and most fragile part?

**Options (after):**
- correct: Backfilling a large table means running an UPDATE across millions of rows, which can lock tables, drive replication lag, or saturate I/O bandwidth on the primary
- distractor_1: Backfills require taking the database offline because the schema isn't yet aware of the new column's data type
- distractor_2: Backfills must be run from inside a Lambda function because RDS doesn't support large UPDATE operations from regular client connections
- distractor_3: Backfills require the application code to be in maintenance mode so that no writes happen during the data migration

**6-month-candidate justification for any touched distractor:** none touched. (Note: "During an expand-contract" failed the `\bDuring\s+a\s+` marker because of "an" vs "a"; reframe re-leads with "Your team".)

### cicd-001-mcq-1 — DROPPED TO TIER 3 (Stephen ruling) — least confident: YES

**Before stem:** What's the distinction between Continuous Delivery and Continuous Deployment?
**After stem:** Your team automatically builds, tests, and stages every change so it is ready to ship, but a human still clicks to push the final release to production. A teammate calls this Continuous Deployment. Which statement correctly distinguishes Continuous Delivery from Continuous Deployment?

**Options (after):**
- correct: Continuous Delivery makes every change deployable to production; Continuous Deployment automatically deploys every successful build to production
- distractor_1: Continuous Delivery deploys to staging only; Continuous Deployment deploys to staging and then production with a manual promotion step
- distractor_2: Continuous Delivery refers to deploying compiled artifacts; Continuous Deployment refers to deploying source code or containers directly
- distractor_3: Continuous Delivery deploys on a fixed schedule; Continuous Deployment deploys whenever the engineer manually triggers a release

**Why I'm least confident:** This is a definitional compare question at heart, so the scenario is partly framing rather than a problem to solve. I added a concrete situation (manual click = Delivery) plus a teammate's misnomer to give the "distinguish them" ask a reason to exist; the correct option still answers cleanly and the distractors remain real misconceptions. The mild risk is that the scenario describes Delivery while a teammate mislabels it Deployment — I judge this *helps* (it forces the candidate to apply the distinction) rather than leaking the answer, but flagging for your read.
**6-month-candidate justification for any touched distractor:** none touched.

### cicd-051-mcq-2 — Tier 1 (CLEARED / at-bar, Stephen ruling) — least confident: YES

**Before stem:** Which lesson would a pipeline owner most likely take from running a CI/CD system through 18 months of production?
**After stem:** An engineer has run a team's CI/CD system in production for 18 months. Which lesson would they most likely take away from that experience?

**Options (after):**
- correct: Reduce batch size — large infrequent merges produce most incidents; small, frequent merges produce most boring uneventful deploys
- distractor_1: Centralise everything — replace decentralised team pipelines with a single org-wide pipeline that all changes flow through for consistency
- distractor_2: Add gates — every deploy should pass through at least 5 approval gates to ensure no change reaches production without sign-off
- distractor_3: Move to a custom in-house CI system — third-party CI tools (GitHub Actions, GitLab) cannot meet the reliability needs of mature pipelines

**Why I'm least confident:** The stem is inherently a judgement/"most likely lesson" question rather than a single-fact scenario. It is at-bar in the pilot sense (experience-distilled opinion with one clearly-correct answer and three plausible-but-wrong takes), and the reframe only swaps the recall lead-in for a concrete actor + "in production". No structural NOT/superlative problem (it's "most likely", with a factual best answer). Flagging only because the genre is softer than the rest of the batch.

## Decision (Stephen, 2026-06-02)

**Approved: 15 of 16 as Tier-1 reframes. cicd-001-mcq-1 dropped to Tier 3.**

- `cicd-051-mcq-2` — cleared / at-bar: judgement genre was inherent pre-reframe, testability already settled at GATE 1, not a superlative.
- `cicd-001-mcq-1` — dropped to Tier 3: the inertness is in the options (abstract definition-pairs), not the stem; a Tier-1 stem reword cannot make it applied. Rationale logged in `tracking.json → tier3_absorption_queue` and the self-assessment section above. Bank stem reverted to original.

Final: drift PASS (touched_count=15), validate PASS, 15 question lines changed across 3 banks, options/explanation byte-identical. Cumulative Tier-1 dropout: 2/49 = 4.08%.
