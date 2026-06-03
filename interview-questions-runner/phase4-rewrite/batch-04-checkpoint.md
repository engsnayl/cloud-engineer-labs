# Batch T1.4 checkpoint

**Tier:** 1  **Slice:** Terraform (14) + Linux (8) D-only  **Date:** 2026-06-02

## Audit script result on batch

- Drift check: **PASS** — `{touched_count: 22, touched_still_flagged: [], regressions: [], result: "PASS"}`
- New audit re-flags on touched IDs: none
- Validate script: **PASS** (interview-1/2/3.json all exit 0; only pre-existing option-length soft warnings, none introduced)
- Pilot-dupe pre-flight: 0 byte-identical-to-pilot in slice
- Pre-apply `classify_stem()` check: all 22 reframed stems classify as `scenario`, 0 trip the NOT/never C-flag
- Bank diff scope: exactly 22 `question` lines changed; options + explanation byte-identical before↔after

## Three-way recall-stem split (per the refined rule, Stephen 2026-06-02)

Each flagged item got the cicd-001 option-test: *can a real troubleshooting scenario make the recall fact load-bearing with the existing options unchanged?*

**Final disposition after Stephen's ruling (2026-06-03): tf-012-mcq-2 moved Bucket 1 → Bucket 2.**

| Bucket | Disposition | Count | IDs |
|---|---|---|---|
| **1 — Tier-1 reframe** | applied reframe, options unchanged | **21** | all below except tf-012-mcq-2 |
| **2 — Tier-3 rewrite-dropout** | cicd-001 structure, option rewrite needed | **1** | tf-012-mcq-2 |
| **3 — Intentional-recall exempt** | legitimately recall, passes as-is | **0** | — |

**Bucket 1 (21):** tf-001-mcq-1, tf-001-mcq-2, tf-003-mcq-1, tf-004-mcq-2, tf-005-mcq-2, tf-006-mcq-1, tf-006-mcq-2, tf-007-mcq-1, tf-007-mcq-2, tf-008-mcq-1, tf-008-mcq-2, tf-009-mcq-2, tf-013-mcq-2, linux-002-mcq-1, linux-003-mcq-2, linux-004-mcq-2, linux-005-mcq-1, linux-005-mcq-2, linux-006-mcq-1, linux-007-mcq-1, linux-007-mcq-2

**Bucket 2 (1):** tf-012-mcq-2 — cicd-001 signature (abstract-comparison ask + definition-pair options, scenario severable from option selection). Bank stem reverted; queued for Tier-3 rewrite that rebuilds options into scenario-classifications.

**Why no Bucket 2/3 here:**
- The classic pure-recall topics the rule anticipated are largely absent from this slice: **no octal-permissions item** at all; the only signal item (linux-002) and the only flag-recall item (linux-007-mcq-1 `set -euo pipefail`) both gain a genuine troubleshooting payoff under reframe (unresponsive-process / script-kept-running-on-error symptoms make the correct option load-bearing). So they are Bucket 1, not Bucket 3.
- Several Linux items (linux-005-mcq-1, linux-005-mcq-2) were *already* diagnostic scenarios (`df` vs `du`, `df -i`) — they only failed D because the stem didn't lead with a recognised actor; the reframe just re-leads with "An engineer …".
- Most Terraform items have concrete-artifact options (commands, flags, file layouts, lock behaviours), so an applied reframe works trivially with options unchanged.

## Trigger checks

- **≥9 of 22 recall drop-outs:** not fired (0 drop-outs).
- **≥4 of 8 Linux items in Bucket 2 or 3:** not fired (0 of 8). The Linux slice was *not* mis-scoped — every Linux item supports an applied reframe.

## borderline_approved counter

Confirmed **still 1** (`k8s-004-mcq-2` only). No new invented-identifier-as-transferred-model cases this batch. (The tf-012 borderline below is a Bucket-1-vs-2 *structural* call, a different axis — not an at-bar distractor judgment, so it does not touch this counter.)

## Session context status

- Estimated context usage: ~35–40% (under 50%)
- Handoff recommended: no — fine to continue to T1.5 this session if approved
- Notes: batches authored this session: T1.3 (committed) + T1.4 (this checkpoint)

## Self-assessment numbers

- MCQs attempted (reframe-attempts): 22
- MCQs completed at tier: **21** (all pure Tier-1 stem-only reframes)
- Dropouts to Tier 3: **1** (tf-012-mcq-2, Bucket 2)
- Intentional-recall exemptions: 0 (not counted in the dropout rate)
- Fabrications caught at self-review: 0 (no distractors touched — stem-only)
- Distractor swaps applied: 0
- Running Tier 1 dropout rate after this batch: **4.23%** (3 of 71 reframe-attempts across T1.1–T1.4; T1.1: 1, T1.2: 0, T1.3: 1, T1.4: 1) — exemptions excluded from this rate, as instructed

## Sample MCQs from this batch

### tf-012-mcq-2 — DROPPED TO TIER 3 (Bucket 2, Stephen ruling 2026-06-03) — least confident: YES (borderline 1↔2)

**Before stem:** Compare `terraform state mv` and `terraform import`.
**After stem:** An engineer moved a resource block into a child module, and `terraform plan` now wants to destroy and recreate it. Which command updates state to the new address without touching the live resource, and how does that differ from `terraform import`?

**Options (after, unchanged):**
- correct: `state mv` moves an existing in-state resource to a new address; `import` brings an out-of-state live resource into state at a given address
- distractor_1: Both commands do the same thing; `import` is the older name and `state mv` is the new name introduced in Terraform 1.0
- distractor_2: `state mv` is for moving resources between modules; `import` is for moving resources between Terraform workspaces in the same backend
- distractor_3: `state mv` requires the resource to exist in both old and new positions in the configuration; `import` requires the resource to exist only in the source address of the state file

**Why I'm least confident / borderline:** the options are comparative definition-pairs (each defines *both* commands), which is the cicd-001 shape. I placed it in **Bucket 1** because — unlike cicd-001 — there is a real troubleshooting payoff: "resource being destroyed after a module move → `state mv`" makes the correct option load-bearing, and the `import` half is supporting contrast rather than the thing being tested. If you read it as cicd-001-structural (the candidate still answers by recognising the right definition, not by reasoning the scenario), it's a one-item move to Bucket 2 (Tier-3 rewrite). Surfacing for your ruling rather than auto-deciding.
**6-month-candidate justification for any touched distractor:** none touched.

### linux-002-mcq-1 — Tier 1 (Bucket 1) — least confident: no (recall-topic, but payoff is real)

**Before stem:** What's the practical difference between SIGTERM and SIGKILL?
**After stem:** An engineer sends a process a graceful shutdown signal, but it ignores the request and keeps running. What's the practical difference between SIGTERM and SIGKILL that explains this?

**Options (after, unchanged):**
- correct: SIGTERM (15) can be caught or ignored by the process and allows graceful shutdown; SIGKILL (9) is forced by the kernel and cannot be caught, blocked, or handled
- distractor_1: SIGTERM kills the process immediately; SIGKILL gives the process 30 seconds to clean up before forced termination
- distractor_2: SIGTERM only works on background processes; SIGKILL is required for foreground processes and shell builtins
- distractor_3: SIGTERM is the legacy signal name; SIGKILL is its modern replacement and both have identical behaviour in current Linux kernels

**Note:** this is the textbook recall-topic case from the refined rule. It stays Bucket 1 (not Bucket 3-exempt) because the unresponsive-process scenario makes the correct option's content ("SIGTERM can be caught/ignored") the actual explanation of the symptom — an applied framing that adds genuine test value.
**6-month-candidate justification for any touched distractor:** none touched.

### linux-005-mcq-1 — Tier 1 (Bucket 1) — least confident: no

**Before stem:** `df -h` reports 95% full but `du -sh /*` totals only 60% of the disk. What's the most likely cause?
**After stem:** An engineer sees `df -h` report a disk 95% full, but `du -sh /*` totals only 60% of the disk. What's the most likely cause?

**Options (after, unchanged):**
- correct: A process has a deleted-but-open file holding inode space — the file is gone from the directory tree (du can't see it) but the inode lives until the process closes the descriptor
- distractor_1: df reports compressed-on-disk size while du reports uncompressed; the difference is the filesystem's compression overhead
- distractor_2: df includes the journal and metadata while du only includes user data; the gap is the filesystem's overhead
- distractor_3: du was run without sudo and missed files in directories the user can't read, accounting for the discrepancy

**Note:** already a diagnostic scenario; only failed D because the stem led with "`df -h`" rather than a recognised actor. Reframe re-leads with "An engineer sees …" (options/explanation untouched).
**6-month-candidate justification for any touched distractor:** none touched.

## Decision (Stephen, 2026-06-03)

**Approved: 21 of 22 as Tier-1 reframes. tf-012-mcq-2 dropped to Tier 3 (Bucket 2).**

- `tf-012-mcq-2` — Bucket 2: cicd-001 signature (abstract-comparison ask + definition-pair options; scenario severable, answerable on recall). Bank stem reverted to original; queued for Tier-3 rewrite that rebuilds options into scenario-classifications (e.g. already-managed resource → import is wrong). Rationale logged in `tracking.json → tier3_absorption_queue`.

Final: drift PASS (touched_count=21), validate PASS, 21 question lines changed across 3 banks, options/explanation byte-identical. Cumulative Tier-1 dropout: 3/71 = 4.23%. `borderline_approved` unchanged at 1. Neither trigger fired.

**New triage step adopted for T1.5 onward** (apply at read-back, before authoring): pre-flag any item whose ask is an abstract comparison ("how does X differ from Y" / "distinguish X from Y") **and** whose options are definition-pairs → route straight to the Tier-3 candidate list in the read-back for up-front confirmation, rather than authoring a Tier-1 reframe. Functional-selection asks over concrete-artifact options (signal names, flags) stay Tier-1; **linux-002-mcq-1 is the reference case for what stays**.
