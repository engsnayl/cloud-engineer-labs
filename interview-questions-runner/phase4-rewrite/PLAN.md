# Phase 4 — MCQ Rewrite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bring the 126 flagged MCQs in `cloud-labs/lab-095-interview-drill-mcq/questions/interview-{1,2,3}.json` up to the pilot-bar quality defined in `interview-questions-runner/Interview-Drill-Runner.md` Appendix A, using a tiered rewrite-in-place strategy driven by a tightened rubric.

**Architecture:** A new working directory `interview-questions-runner/phase4-rewrite/` holds per-batch rewrite artifacts, a running tracking file, and checkpoint reports. Each batch reads the current bank files, applies tier-specific transforms to a slice of MCQs, writes the touched MCQs to a batch JSON, validates and audits the batch in isolation, applies the changes back to the bank files, then re-audits the full banks. A gate before Tier 1 surfaces a 6-MCQ control sample from the 82 unflagged MCQs so we can confirm the audit's "unflagged = at bar" assumption before committing hours to the flagged 126.

**Tech Stack:** Python 3 (existing `scripts/audit.py`, `scripts/audit_suspect.py`, `scripts/validate_mcqs.py`); a new `scripts/check_drift.py`; JSON for all data; markdown for checkpoint reports.

---

## Tightened rubric (operationalised)

Every distractor authored or rewritten in Tiers 2 and 3, and every distractor that is re-evaluated during a Tier 1 stem reframe, must pass this explicit self-check:

> **6-month-candidate test (operationalised "A_fabricated" check):**
> "Could a real candidate with ~6 months of cloud experience but no deep knowledge of this specific feature actually believe this distractor? If answering requires inventing a feature, version, billing detail, or limit that doesn't exist, replace it."

Other rubric tightenings (apply when a stem or option is touched):

- **≥70% scenario stems** across the bank — the rewrite must not regress this ratio. Pure recall ("What is X?") allowed only when recall is genuinely the testable point (octal permissions, port numbers, defaults).
- **Match-style MCQs may include at most one full scramble.** Other distractors must be partial-correct (almost right, one relationship wrong) or different framing (e.g., "all of these do the same thing").
- **No "NOT" / "which is not" stems. No "essentially never" correct options.** Either reframe to a scenario where one positive option is the right answer, or move to a different facet of the source.
- **Two MCQs from one source must test distinct facets** — re-check during Tier 3 reauthoring especially.

---

## File Structure

**New artifacts (created by this plan):**

- Create: `interview-questions-runner/phase4-rewrite/PLAN.md` (this file)
- Create: `interview-questions-runner/phase4-rewrite/README.md` (orienting doc)
- Create: `interview-questions-runner/phase4-rewrite/tracking.json` (running counters, drop-out log)
- Create: `interview-questions-runner/phase4-rewrite/baseline-snapshot.json` (snapshot of `draft-audit.json` before any rewrite work, so drift can be diffed against it)
- Create: `interview-questions-runner/phase4-rewrite/control-sample.json` (6 unflagged MCQs sampled for pre-Tier-1 sanity check)
- Create: `interview-questions-runner/phase4-rewrite/control-sample-checkpoint.md`
- Create: `interview-questions-runner/phase4-rewrite/batch-NN-tierK-slug.json` (one per batch — touched MCQs only, with self-check records embedded)
- Create: `interview-questions-runner/phase4-rewrite/batch-NN-checkpoint.md` (one per batch — surfaced to Stephen)
- Create: `interview-questions-runner/scripts/check_drift.py` (mechanised drift check)
- Create: `interview-questions-runner/scripts/sample_unflagged.py` (one-shot helper to pick the 6 control MCQs)

**Modified by the work (not by the plan):**

- Modify: `cloud-labs/lab-095-interview-drill-mcq/questions/interview-1.json`
- Modify: `cloud-labs/lab-095-interview-drill-mcq/questions/interview-2.json`
- Modify: `cloud-labs/lab-095-interview-drill-mcq/questions/interview-3.json`

**Read-only references:**

- `interview-questions-runner/Interview-Drill-Runner.md` — canonical rubric; Appendix A samples
- `interview-questions-runner/phase2-pilot/pilot.json` — 10 pilot MCQs at the bar (use as templates)
- `interview-questions-runner/phase3-audit/flagged-mcqs.json` — 126 flagged IDs with reason
- `interview-questions-runner/phase3-audit/draft-audit.json` — full per-MCQ heuristic output
- `interview-questions-runner/scripts/audit.py` — produces `draft-audit.json`; hardcoded paths
- `interview-questions-runner/scripts/audit_suspect.py` — produces `suspect-distractors.json`
- `interview-questions-runner/scripts/validate_mcqs.py` — schema + style validator

---

## Tier slicing (locked)

| Batch | Tier | Slice | Size |
|---|---|---|---|
| Control | n/a | 6 random unflagged MCQs | 6 |
| T1.1 | 1 | AWS D-only | 17 |
| T1.2 | 1 | Kubernetes D-only | 18 |
| T1.3 | 1 | CI/CD D-only | 16 |
| T1.4 | 1 | Terraform D-only + Linux D-only | 14 + 8 = 22 |
| T1.5 | 1 | Docker D-only + Git D-only | 13 + 8 = 21 |
| T2.1 | 2 | A-only (AWS 4, CI/CD 4, K8s 2, Git 1) | 11 |
| T3.1 | 3 | Structural: AWS, K8s, CI/CD (4+5+4) | 13 |
| T3.2 | 3 | Structural: TF, Docker, Linux (4+3+1) | 8 |

Sizes deliberately fall in 13–22 range. Domain coherence per batch keeps related distractor research loaded together.

---

## Schemas

### `tracking.json`

```json
{
  "baseline_flagged_count": 126,
  "baseline_snapshot_path": "interview-questions-runner/phase4-rewrite/baseline-snapshot.json",
  "control_sample_status": "pending | approved | expanded_audit",
  "batches": [
    {
      "batch_id": "T1.1",
      "tier": 1,
      "domain_slice": "aws",
      "mcq_ids_attempted": ["aws-...-mcq-N"],
      "mcqs_completed": 17,
      "mcqs_dropped_to_tier3": 0,
      "drop_out_ids": [],
      "distractor_self_check_records": 0,
      "fabrications_caught_at_selfreview": 0,
      "audit_reflag_ids_after_batch": [],
      "validate_mcqs_status": "pass | fail",
      "checkpoint_date": "YYYY-MM-DD",
      "status": "pending | approved | revised"
    }
  ],
  "running_totals": {
    "tier1_dropouts_to_tier3": 0,
    "tier1_dropout_rate_pct": 0,
    "tier2_fabrications_caught": 0,
    "tier3_full_rewrites": 0,
    "total_audit_reflags": 0
  }
}
```

### Batch JSON (`batch-NN-tierK-slug.json`)

```json
{
  "batch_id": "T1.1",
  "tier": 1,
  "domain_slice": "aws",
  "rewrites": [
    {
      "mcq_id": "aws-002-mcq-1",
      "source_bank": 1,
      "tier_applied": 1,
      "change_summary": "stem reframed from definition to scenario",
      "before": {
        "question": "...",
        "options": {"correct": "...", "distractor_1": "...", "distractor_2": "...", "distractor_3": "..."},
        "explanation": "..."
      },
      "after": {
        "question": "...",
        "options": {"correct": "...", "distractor_1": "...", "distractor_2": "...", "distractor_3": "..."},
        "explanation": "..."
      },
      "distractor_self_check": [
        {
          "key": "distractor_2",
          "touched": false,
          "still_fits_new_stem": true,
          "real_misconception": "candidate confuses MapPublicIpOnLaunch with the route-table criterion"
        }
      ],
      "dropped_to_tier3": false,
      "drop_reason": null
    }
  ]
}
```

For Tier 1, `before.options == after.options` and `before.explanation == after.explanation` in the success case (stem-only change). If a stem reframe forces option/explanation changes, the rewrite is **dropped to Tier 3** instead — set `dropped_to_tier3: true` with a one-sentence `drop_reason`, leave the bank file unchanged for that MCQ, and surface it in the checkpoint.

For Tier 2, only the named A-flagged distractor is touched; the `distractor_self_check` entry for that key must have `touched: true` and a substantive `real_misconception` field.

For Tier 3, expect full rewrites; all four `distractor_self_check` entries should be reasoned through.

### Checkpoint markdown (`batch-NN-checkpoint.md`)

A fixed template surfaced after each batch:

```markdown
# Batch [ID] checkpoint

**Tier:** [1|2|3]  **Slice:** [domain(s)]  **Date:** YYYY-MM-DD

## Audit script result on batch

- Drift check: [PASS | FAIL — details]
- New audit re-flags on touched IDs: [list or "none"]
- Validate script: [PASS | FAIL — details]

[If FAIL on audit drift: STOP HERE — drift-only checkpoint per execution discipline rule 2. Do not include sample review, self-assessment, false-positive section, or decision-request until drift is resolved.]

## Session context status

- Estimated context usage: [under 50% | 50–65% | over 65%]
- Handoff recommended: [no | yes — start a fresh Claude Code session before the next batch; resume from this checkpoint's tracking.json state]
- Notes: [optional, e.g., "previous batches in this session: N" or "approaching cache TTL"]

## Self-assessment numbers

- MCQs attempted: N
- MCQs completed at tier: N
- Dropouts to Tier 3: N (IDs: ...)
- Fabrications caught at self-review (rejected before commit): N
- Distractor swaps applied: N
- Running Tier 1 dropout rate after this batch: X% (vs 20–30% estimate)

## Sample MCQs from this batch

3–4 selected MCQs, **including the 1–2 I'm least confident on**, in this format:

### [mcq_id] — [tier applied] — [least confident: yes/no]

**Before stem:** ...
**After stem:** ...

**Options (after):**
- correct: ...
- distractor_1: ...
- distractor_2: ...
- distractor_3: ...

**Why I'm least confident:** [if flagged as such, one or two sentences]
**6-month-candidate justification for any touched distractor:** ...

## False-positive verifications (Tier 2 batches only)

For each Tier 2 MCQ where the suspect-distractor was verified as a real misconception on review (no change applied):

- **mcq_id:** ...
- **suspect_distractor_key:** ...
- **suspect-script pattern that flagged it:** ...
- **Why it's actually a real misconception:** one sentence
- **Heuristic recommendation:** keep / tighten / drop — and how

These records refine `audit_suspect.py` for future banks; they're not just exceptions.

## Decision requested

Approve / revise / expand audit scope.
```

---

## Task 0: Build the drift-check script

**Files:**
- Create: `interview-questions-runner/scripts/check_drift.py`

The script mechanises the user's requirement: after every batch, automatically check whether (a) any of the IDs we just "fixed" still flag, or (b) any previously-unflagged ID has newly become flagged.

- [ ] **Step 1: Pre-flight — verify source material is available**

The rewrite needs `Interview-Prep-Combined.md` from the parent repo as the source of truth for each MCQ's underlying concept. Two acceptable local paths:

1. `~/interview-prep-app/Interview-Prep-Combined.md` — Pi convention from the brief
2. `Interview Prep App/Interview-Prep-Combined.md` (relative to repo root) — Windows dev location when the source repo is checked out alongside the lab repo

Verify one of them exists; clone if neither:

```bash
if [ -f ~/interview-prep-app/Interview-Prep-Combined.md ]; then
  echo "FOUND: ~/interview-prep-app/Interview-Prep-Combined.md"
  ls -la ~/interview-prep-app/Interview-Prep-Combined.md
elif [ -f "Interview Prep App/Interview-Prep-Combined.md" ]; then
  echo "FOUND: Interview Prep App/Interview-Prep-Combined.md (repo-root)"
  ls -la "Interview Prep App/Interview-Prep-Combined.md"
else
  git clone https://github.com/engsnayl/interview-prep-app ~/interview-prep-app
  ls -la ~/interview-prep-app/Interview-Prep-Combined.md
fi
```

Expected: file exists, size > 0 (current size ~675KB). The file's first line should be `# Interview Prep — Combined Reference`. Subsequent tier-batch tasks should read from whichever path resolved.

If cloning fails (offline, auth required), fall back to fetching the raw file once via WebFetch from `https://raw.githubusercontent.com/engsnayl/interview-prep-app/main/Interview-Prep-Combined.md` and saving it locally to `~/interview-prep-app/Interview-Prep-Combined.md`. Source must be available before any tier batch starts.

- [ ] **Step 2: Create the drift-check script with this exact content**

```python
"""Drift check — runs after every Phase 4 batch.

Logic:
  1. Re-run scripts/audit.py to refresh draft-audit.json from the current
     bank files.
  2. Read the batch JSON to get the list of MCQ ids the batch touched.
  3. Compare new draft-audit.json against baseline-snapshot.json:
       - touched ids: any that still carry flags  -> drift (failed fix)
       - non-touched ids: any newly flagged       -> drift (regression)
  4. Exit 0 with summary on PASS. Exit 1 with detail on FAIL.

Usage:
  python interview-questions-runner/scripts/check_drift.py \
      interview-questions-runner/phase4-rewrite/batch-01-tier1-aws.json
"""

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
AUDIT_SCRIPT = ROOT / "interview-questions-runner" / "scripts" / "audit.py"
DRAFT_AUDIT = ROOT / "interview-questions-runner" / "phase3-audit" / "draft-audit.json"
BASELINE = ROOT / "interview-questions-runner" / "phase4-rewrite" / "baseline-snapshot.json"


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def main():
    if len(sys.argv) != 2:
        print("usage: check_drift.py <batch-json-path>", file=sys.stderr)
        sys.exit(2)
    batch_path = Path(sys.argv[1])
    batch = load_json(batch_path)
    touched_ids = {r["mcq_id"] for r in batch["rewrites"] if not r.get("dropped_to_tier3")}

    # 1. Refresh draft-audit.json by invoking the audit module
    result = subprocess.run(
        [sys.executable, str(AUDIT_SCRIPT)],
        cwd=str(ROOT),
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print("audit.py failed:", result.stderr, file=sys.stderr)
        sys.exit(2)

    new_rows = load_json(DRAFT_AUDIT)
    new_by_id = {r["id"]: r for r in new_rows}

    if not BASELINE.exists():
        print("baseline-snapshot.json missing — create it before the first batch", file=sys.stderr)
        sys.exit(2)
    baseline_rows = load_json(BASELINE)
    baseline_flagged_ids = {r["id"] for r in baseline_rows if r["flags"]}

    # 2. Drift A: touched id still flagged
    still_flagged = []
    for mid in sorted(touched_ids):
        row = new_by_id.get(mid)
        if row is None:
            still_flagged.append((mid, ["MISSING_FROM_AUDIT"]))
        elif row["flags"]:
            still_flagged.append((mid, row["flags"]))

    # 3. Drift B: regression — previously unflagged, now flagged
    new_flagged_ids = {r["id"] for r in new_rows if r["flags"]}
    regressions = sorted(new_flagged_ids - baseline_flagged_ids - touched_ids)

    fail = bool(still_flagged or regressions)
    summary = {
        "batch_id": batch.get("batch_id"),
        "touched_count": len(touched_ids),
        "touched_still_flagged": still_flagged,
        "regressions": regressions,
        "result": "FAIL" if fail else "PASS",
    }
    print(json.dumps(summary, indent=2))
    sys.exit(1 if fail else 0)


if __name__ == "__main__":
    main()
```

- [ ] **Step 3: Smoke-test on an empty fake batch to confirm the script runs**

```bash
cd /c/Users/naylo/Labs/cloud-engineer-labs
python -c "import json; json.dump({'batch_id':'smoke','rewrites':[]}, open('/tmp/smoke_batch.json','w'))"
python interview-questions-runner/scripts/check_drift.py /tmp/smoke_batch.json
```

Expected: exits 2 with "baseline-snapshot.json missing" (we haven't created it yet — Task 1 does that). This proves the script loads.

- [ ] **Step 4: Commit**

```bash
git add interview-questions-runner/scripts/check_drift.py
git commit -m "phase4: add drift-check script for batch-level audit comparison"
```

---

## Task 1: Set up phase4 directory and baseline snapshot

**Files:**
- Create: `interview-questions-runner/phase4-rewrite/README.md`
- Create: `interview-questions-runner/phase4-rewrite/tracking.json`
- Create: `interview-questions-runner/phase4-rewrite/baseline-snapshot.json` (copy of current draft-audit.json)

- [ ] **Step 1: Write the README**

```markdown
# Phase 4 — MCQ rewrite

Acts on the 126 flagged MCQs identified in `../phase3-audit/`. Implements
the tiered rewrite-in-place strategy defined in `PLAN.md`.

## Files

- `PLAN.md` — the implementation plan
- `tracking.json` — running counters and per-batch records
- `baseline-snapshot.json` — frozen copy of `../phase3-audit/draft-audit.json`
  from before any rewrite work, used by `scripts/check_drift.py` to detect
  regressions
- `control-sample.json` / `control-sample-checkpoint.md` — pre-Tier-1 control
- `batch-NN-tierK-slug.json` — per-batch rewrite output
- `batch-NN-checkpoint.md` — per-batch checkpoint surfaced to Stephen
```

- [ ] **Step 2: Refresh draft-audit.json from current state, then snapshot it as baseline**

```bash
cd /c/Users/naylo/Labs/cloud-engineer-labs
python interview-questions-runner/scripts/audit.py
cp interview-questions-runner/phase3-audit/draft-audit.json \
   interview-questions-runner/phase4-rewrite/baseline-snapshot.json
```

Expected output from audit.py: `MCQs with any flag (C or D): 115`. Categories A and B are not detected by audit.py — they come from `audit_suspect.py` + manual review, which is why the consolidated `flagged-mcqs.json` count is 126 (115 + 11 A-only). The snapshot freezes the 115 audit.py mechanically detects, which is what the drift check uses to spot regressions (touched id still flagged, or newly-flagged id from previously-clean set).

- [ ] **Step 3: Initialise tracking.json**

```json
{
  "baseline_flagged_count": 126,
  "baseline_snapshot_path": "interview-questions-runner/phase4-rewrite/baseline-snapshot.json",
  "control_sample_status": "pending",
  "batches": [],
  "running_totals": {
    "tier1_dropouts_to_tier3": 0,
    "tier1_dropout_rate_pct": 0,
    "tier2_fabrications_caught": 0,
    "tier3_full_rewrites": 0,
    "total_audit_reflags": 0
  }
}
```

- [ ] **Step 4: Re-run the drift-check smoke test against a real (empty) batch to confirm baseline is wired**

```bash
python -c "import json; json.dump({'batch_id':'smoke','rewrites':[]}, open('/tmp/smoke_batch.json','w'))"
python interview-questions-runner/scripts/check_drift.py /tmp/smoke_batch.json
```

Expected: exits 0 with `"result": "PASS"` and `"touched_count": 0` — no touched ids means no drift A; same audit as baseline means no drift B.

- [ ] **Step 5: Commit**

```bash
git add interview-questions-runner/phase4-rewrite/README.md \
        interview-questions-runner/phase4-rewrite/tracking.json \
        interview-questions-runner/phase4-rewrite/baseline-snapshot.json \
        interview-questions-runner/phase4-rewrite/PLAN.md
git commit -m "phase4: scaffold rewrite directory and baseline snapshot"
```

---

## Task 2: Sample 6 unflagged MCQs for the control check

**Files:**
- Create: `interview-questions-runner/scripts/sample_unflagged.py`
- Create: `interview-questions-runner/phase4-rewrite/control-sample.json`
- Create: `interview-questions-runner/phase4-rewrite/control-sample-checkpoint.md`

The audit says 82 MCQs are unflagged. The user wants 6 of those reviewed before we commit hours to rewriting the 126, so we can catch the case where "unflagged ≠ at bar."

- [ ] **Step 1: Write the sampler script**

```python
"""Pick 6 unflagged MCQs at random, spread across domains and banks.

Reads:
  - cloud-labs/lab-095-interview-drill-mcq/questions/interview-{1,2,3}.json
  - interview-questions-runner/phase3-audit/flagged-mcqs.json
Writes:
  - interview-questions-runner/phase4-rewrite/control-sample.json

Seeded so re-runs are reproducible; if Stephen wants a different sample,
override seed via SAMPLE_SEED env var.
"""

import json
import os
import random
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
QDIR = ROOT / "cloud-labs" / "lab-095-interview-drill-mcq" / "questions"
FLAGGED = ROOT / "interview-questions-runner" / "phase3-audit" / "flagged-mcqs.json"
OUT = ROOT / "interview-questions-runner" / "phase4-rewrite" / "control-sample.json"

SEED = int(os.environ.get("SAMPLE_SEED", "4096"))


def main():
    flagged_ids = {r["id"] for r in json.loads(FLAGGED.read_text(encoding="utf-8"))}
    by_domain = defaultdict(list)
    for b in (1, 2, 3):
        for m in json.loads((QDIR / f"interview-{b}.json").read_text(encoding="utf-8")):
            if m["id"] not in flagged_ids:
                m_with_bank = dict(m)
                m_with_bank["bank"] = b
                by_domain[m["domain"]].append(m_with_bank)

    rng = random.Random(SEED)
    domains = sorted(by_domain.keys())
    rng.shuffle(domains)

    # Take 1 per domain until we have 6; if a domain has none unflagged, skip it.
    picked = []
    for d in domains:
        if len(picked) == 6:
            break
        pool = by_domain[d]
        if not pool:
            continue
        picked.append(rng.choice(pool))

    # If we ran out of domains (only 7 domains total but some may be empty),
    # top up from the largest remaining domain pool.
    if len(picked) < 6:
        remaining = [m for d in domains for m in by_domain[d] if m["id"] not in {p["id"] for p in picked}]
        rng.shuffle(remaining)
        picked.extend(remaining[: 6 - len(picked)])

    OUT.write_text(json.dumps(picked, indent=2), encoding="utf-8")
    print(f"Wrote {len(picked)} control-sample MCQs to {OUT}")
    for m in picked:
        print(f"  {m['id']:25s} bank={m['bank']} domain={m['domain']}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run it**

```bash
cd /c/Users/naylo/Labs/cloud-engineer-labs
python interview-questions-runner/scripts/sample_unflagged.py
```

Expected: 6 MCQs picked, one per domain (where possible), printed with their IDs.

- [ ] **Step 3: Write the control-sample checkpoint markdown**

For each of the 6 sampled MCQs, evaluate against Appendix A bar and the tightened rubric. For each one, the checkpoint records:

```markdown
# Control sample — 6 unflagged MCQs

**Purpose:** Confirm the 82 "unflagged" MCQs are actually at the pilot bar before committing to rewriting the flagged 126. If the unflagged work is weaker than the audit thinks, expand the audit scope before Tier 1 starts.

**Seed:** SAMPLE_SEED=4096

## Per-MCQ assessment

### [mcq_id] — [domain] — bank N

**Stem:** ...
**Correct:** ...
**Distractors:** ...
**Explanation:** ...

**Tightened-rubric assessment:**
- Stem type (scenario / definition / match): ...
- For each distractor, apply the 6-month-candidate test: pass/fail with one-sentence justification.
- Explanation covers why each distractor fails: yes / no.
- Single-source-pair check (other MCQ from same source_id tests a distinct facet): yes / no — note the other MCQ's testable point.

**Verdict:** at-bar / borderline / fails-rubric

## Aggregate

- At-bar: N / 6
- Borderline: N / 6
- Fails-rubric: N / 6

## Recommendation to Stephen

- If 6/6 at-bar: confirm the 82 are off the table, proceed to Tier 1.
- If 4-5/6 at-bar: proceed but expand spot-check during final re-audit (Task 10).
- If <4/6 at-bar: STOP. Expand audit scope to cover all 208 before any Tier 1 work begins.
```

- [ ] **Step 4: Update tracking.json**

Set `control_sample_status` to `"awaiting_review"` and add the 6 MCQ IDs in a new `control_sample_ids` field.

- [ ] **Step 5: Surface to Stephen — wait for decision before proceeding**

Output to the user:
- The full control-sample-checkpoint.md
- A recommendation: proceed / expand-scope

**GATE:** No subsequent task starts until Stephen approves "proceed to Tier 1" or "expand scope first."

- [ ] **Step 6: Commit (after Stephen's decision)**

```bash
git add interview-questions-runner/scripts/sample_unflagged.py \
        interview-questions-runner/phase4-rewrite/control-sample.json \
        interview-questions-runner/phase4-rewrite/control-sample-checkpoint.md \
        interview-questions-runner/phase4-rewrite/tracking.json
git commit -m "phase4: control sample of 6 unflagged MCQs — [proceed | expand]"
```

---

## Task 3: Batch T1.1 — AWS Tier 1 (17 stem reframes)

**Files:**
- Create: `interview-questions-runner/phase4-rewrite/batch-01-tier1-aws.json`
- Create: `interview-questions-runner/phase4-rewrite/batch-01-checkpoint.md`
- Modify: `cloud-labs/lab-095-interview-drill-mcq/questions/interview-{1,2,3}.json` (in-place updates to the 17 AWS D-only MCQs)
- Modify: `interview-questions-runner/phase4-rewrite/tracking.json`

**Tier 1 procedure (applies to T1.1 through T1.5):**

For each MCQ in the slice:

1. Read current MCQ from the relevant bank file.
2. Reframe the stem from definition form to scenario form. Use pilot-style framing: a concrete actor with a concrete need or observation. The scenario should make the existing correct option the actual answer, not a tangential one.
3. Re-evaluate the 4 existing options against the new stem:
   - Does the correct option still cleanly answer the scenario? (If no → drop to Tier 3.)
   - Does each distractor still represent a real misconception the scenario would elicit? Apply the **6-month-candidate test** to each. (If a distractor no longer fits and there's no obvious replacement that does → drop to Tier 3.)
4. Re-evaluate the explanation: does it still cover why each distractor fails for the new scenario? Light wording touch-ups allowed; structural rewrites mean drop to Tier 3.
5. Record the before/after and per-distractor self-check in the batch JSON.

For each MCQ that stays in Tier 1, apply the change back to the source bank file by matching on `id`. For each MCQ dropped to Tier 3, leave the bank file unchanged for that MCQ and record `dropped_to_tier3: true` with a `drop_reason`.

- [ ] **Step 0: Re-anchor on the pilot voice**

Before any authoring, re-read `interview-questions-runner/phase2-pilot/pilot.json` end-to-end. The pilot is the voice for this tier. Note: scenario framing, distractor patterns (real concept wrong context, half-remembered, what-would-happen-without-X, etc.), explanation structure (one-sentence correct + per-distractor failure mode + one piece of real-world context). This is anchoring, not lookup — do it even if you "remember" the pilot from earlier in the session.

- [ ] **Step 1: Identify the 17 AWS D-only MCQ IDs**

```bash
cd /c/Users/naylo/Labs/cloud-engineer-labs
python -c "
import json
data = json.load(open('interview-questions-runner/phase3-audit/flagged-mcqs.json'))
ids = [x['id'] for x in data if x['flags'] == ['D_definition'] and x['domain'] == 'aws']
print(len(ids))
for i in ids: print(i)
"
```

Expected: 17 IDs printed.

- [ ] **Step 2: For each ID, read current MCQ from the right bank file, perform the Tier 1 procedure, and accumulate batch JSON entries**

This is content authoring work. For each MCQ:
- Load the MCQ from `cloud-labs/lab-095-interview-drill-mcq/questions/interview-{bank}.json`
- Reference `interview-questions-runner/phase2-pilot/pilot.json` for the scenario-stem voice
- Reference the source `Interview-Prep-Combined.md` (clone from `https://github.com/engsnayl/interview-prep-app` if not present locally) for the canonical concept
- Build the before/after record per the schema in PLAN.md "Batch JSON" section
- Apply the **6-month-candidate self-check** to every distractor: if any distractor would have required inventing a feature to fit, drop to Tier 3 instead

Accumulate all 17 records in memory (or write incrementally to the batch JSON), keeping unchanged option/explanation fields where possible.

- [ ] **Step 3: Write the batch JSON file**

```bash
# (Written programmatically as part of step 2 — the file is the batch output)
```

Expected: `batch-01-tier1-aws.json` exists with 17 rewrite records (some possibly `dropped_to_tier3`).

- [ ] **Step 4: Apply non-dropped rewrites back into the bank files**

For each rewrite where `dropped_to_tier3 == false`, update the MCQ in the source bank file in-place (match on `id`), replacing the `question` field (and `options` / `explanation` if changed). Preserve all other fields including order.

Apply via a small one-shot Python script (inline ok):

```python
import json
from pathlib import Path

batch = json.load(open("interview-questions-runner/phase4-rewrite/batch-01-tier1-aws.json"))
qdir = Path("cloud-labs/lab-095-interview-drill-mcq/questions")

# Index rewrites by id
applied = {r["mcq_id"]: r["after"] for r in batch["rewrites"] if not r.get("dropped_to_tier3")}

for b in (1, 2, 3):
    p = qdir / f"interview-{b}.json"
    mcqs = json.load(open(p, encoding="utf-8"))
    for m in mcqs:
        if m["id"] in applied:
            after = applied[m["id"]]
            m["question"] = after["question"]
            m["options"] = after["options"]
            m["explanation"] = after["explanation"]
    p.write_text(json.dumps(mcqs, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
print(f"Applied {len(applied)} rewrites across bank files")
```

- [ ] **Step 5: Run validate_mcqs.py on each bank**

```bash
python interview-questions-runner/scripts/validate_mcqs.py cloud-labs/lab-095-interview-drill-mcq/questions/interview-1.json
python interview-questions-runner/scripts/validate_mcqs.py cloud-labs/lab-095-interview-drill-mcq/questions/interview-2.json
python interview-questions-runner/scripts/validate_mcqs.py cloud-labs/lab-095-interview-drill-mcq/questions/interview-3.json
```

Expected: each exits 0 (no hard schema violations). Soft warnings (length balance) may print — they don't fail.

If any exits non-zero: STOP. Inspect the error, fix the offending MCQ in the batch JSON and re-apply, then re-run validate. Do not proceed until all three pass.

- [ ] **Step 6: Run the drift check**

```bash
python interview-questions-runner/scripts/check_drift.py \
    interview-questions-runner/phase4-rewrite/batch-01-tier1-aws.json
```

Expected: `"result": "PASS"`.

If FAIL (touched id still flagged OR regression):
- **Do not show samples to Stephen.** Surface the failure first, with the script's JSON output.
- Fix: for "touched id still flagged" → the stem reframe was insufficient; revisit that MCQ. For "regression" → something else got re-flagged; inspect new audit output and investigate.

- [ ] **Step 7: Update tracking.json**

Append a batch record with:
- mcq_ids_attempted (the 17 IDs)
- mcqs_completed (17 - dropouts)
- mcqs_dropped_to_tier3 (count + ID list)
- audit_reflag_ids_after_batch (from check_drift output)
- validate_mcqs_status: pass
- Update `running_totals.tier1_dropouts_to_tier3` and recompute `tier1_dropout_rate_pct = dropouts_so_far / attempted_so_far * 100`

- [ ] **Step 8: Write the checkpoint markdown**

Per the checkpoint template in PLAN.md:
- Drift check result (from step 6)
- Validate result (from step 5)
- Self-assessment numbers (from tracking.json)
- 3–4 sample MCQs, including 1–2 least-confident picks, in the format from the template
- "Decision requested: approve / revise / expand audit scope"

- [ ] **Step 9: Surface checkpoint to Stephen — wait for decision**

**GATE:** Do not start Task 4 (T1.2) until Stephen approves or revises this batch.

If revise: pull the cited MCQs back out, redo, repeat steps 3–8 for the revised subset only (mini-batch).

- [ ] **Step 10: Commit (after Stephen's decision)**

```bash
git add interview-questions-runner/phase4-rewrite/batch-01-tier1-aws.json \
        interview-questions-runner/phase4-rewrite/batch-01-checkpoint.md \
        interview-questions-runner/phase4-rewrite/tracking.json \
        cloud-labs/lab-095-interview-drill-mcq/questions/interview-1.json \
        cloud-labs/lab-095-interview-drill-mcq/questions/interview-2.json \
        cloud-labs/lab-095-interview-drill-mcq/questions/interview-3.json
git commit -m "phase4: batch T1.1 — reframe 17 AWS D-only MCQ stems to scenario form"
```

---

## Task 4: Batch T1.2 — Kubernetes Tier 1 (18 stem reframes)

**Identical procedure to Task 3, scoped to the 18 Kubernetes D-only MCQs.**

**Files:**
- Create: `interview-questions-runner/phase4-rewrite/batch-02-tier1-kubernetes.json`
- Create: `interview-questions-runner/phase4-rewrite/batch-02-checkpoint.md`
- Modify: bank files in-place; `tracking.json`

- [ ] **Step 1: Identify the 18 K8s D-only MCQ IDs** — same query as Task 3 step 1, with `domain == 'kubernetes'`.
- [ ] **Step 2: For each ID, perform the Tier 1 procedure** — same as Task 3 step 2, **with K8s-specific consideration: the pilot's K8s sample (`k8s-005-mcq-1`) and Appendix A sample 2 are the voice to match**. Pay particular attention to scheduler/controller/QoS confusions — these are common 6-month-candidate misconceptions and good distractor fodder.
- [ ] **Step 3: Write batch JSON** — `batch-02-tier1-kubernetes.json`.
- [ ] **Step 4: Apply rewrites back into bank files** — same script as Task 3 step 4, with the new batch path.
- [ ] **Step 5: Validate** — same as Task 3 step 5.
- [ ] **Step 6: Drift check** — same as Task 3 step 6, with the new batch path.
- [ ] **Step 7: Update tracking.json** — append T1.2 record; recompute running totals.
- [ ] **Step 8: Write checkpoint** — `batch-02-checkpoint.md`.
- [ ] **Step 9: Surface to Stephen — GATE: wait for approval before Task 5.**
- [ ] **Step 10: Commit.**

```bash
git add interview-questions-runner/phase4-rewrite/batch-02-tier1-kubernetes.json \
        interview-questions-runner/phase4-rewrite/batch-02-checkpoint.md \
        interview-questions-runner/phase4-rewrite/tracking.json \
        cloud-labs/lab-095-interview-drill-mcq/questions/interview-1.json \
        cloud-labs/lab-095-interview-drill-mcq/questions/interview-2.json \
        cloud-labs/lab-095-interview-drill-mcq/questions/interview-3.json
git commit -m "phase4: batch T1.2 — reframe 18 Kubernetes D-only MCQ stems to scenario form"
```

---

## Task 5: Batch T1.3 — CI/CD Tier 1 (16 stem reframes)

**Identical procedure to Task 3.** Slice: 16 CI/CD D-only MCQs.

- [ ] Step 1: Identify 16 CI/CD D-only MCQ IDs (`domain == 'cicd'`).
- [ ] Step 2: Reframe stems. CI/CD-specific consideration: OIDC vs static credentials, workflow vs job vs step scope, runner types, artifact retention — distractor fodder where 6-month candidates plausibly confuse these.
- [ ] Step 3: Write `batch-03-tier1-cicd.json`.
- [ ] Step 4: Apply.
- [ ] Step 5: Validate.
- [ ] Step 6: Drift check.
- [ ] Step 7: Update tracking.json.
- [ ] Step 8: Write `batch-03-checkpoint.md`.
- [ ] Step 9: Surface to Stephen — GATE.
- [ ] Step 10: Commit.

```bash
git add interview-questions-runner/phase4-rewrite/batch-03-tier1-cicd.json \
        interview-questions-runner/phase4-rewrite/batch-03-checkpoint.md \
        interview-questions-runner/phase4-rewrite/tracking.json \
        cloud-labs/lab-095-interview-drill-mcq/questions/interview-1.json \
        cloud-labs/lab-095-interview-drill-mcq/questions/interview-2.json \
        cloud-labs/lab-095-interview-drill-mcq/questions/interview-3.json
git commit -m "phase4: batch T1.3 — reframe 16 CI/CD D-only MCQ stems to scenario form"
```

---

## Task 6: Batch T1.4 — Terraform + Linux Tier 1 (22 stem reframes)

**Identical procedure to Task 3.** Slice: 14 Terraform + 8 Linux D-only MCQs.

- [ ] Step 1: Identify 14 Terraform + 8 Linux D-only MCQ IDs.
- [ ] Step 2: Reframe stems. Terraform-specific consideration: state, locking, count vs for_each, modules — Appendix A sample 3 is the voice. Linux-specific consideration: where recall is genuinely the testable point (octal permissions, signals, `/proc`), keep the stem as recall and explicitly note in the batch record "recall stem retained — see PLAN.md rubric"; the rubric allows ~30% pure-recall.
- [ ] Step 3: Write `batch-04-tier1-terraform-linux.json`.
- [ ] Step 4: Apply.
- [ ] Step 5: Validate.
- [ ] Step 6: Drift check. NOTE: any Linux MCQ where you retained a recall stem will still get flagged D_definition by the audit script — that's expected. The drift check will FAIL on those IDs. Resolution: list those IDs explicitly in the batch JSON with `intentional_recall: true` and skip them in the drift comparison, OR handle them as Tier-3 reauthoring. **For first execution, treat intentional-recall as a drop-to-Tier-3** — keep the drift check honest. We can introduce an "intentional recall" exception in a later iteration if dropouts here are high.
- [ ] Step 7: Update tracking.json.
- [ ] Step 8: Write `batch-04-checkpoint.md`. Include a section **"Recall-stem drop-outs"** listing each MCQ where the stem was a genuine pure-recall and got dropped to Tier 3 under the intentional-recall default. **If recall-stem drop-outs alone exceed ~40% of this batch's slice (≥9 of 22), flag this prominently with a recommendation to revisit the intentional-recall exception** — the policy may be over-rejecting legitimate recall MCQs.
- [ ] Step 9: Surface to Stephen — GATE.
- [ ] Step 10: Commit.

```bash
git add interview-questions-runner/phase4-rewrite/batch-04-tier1-terraform-linux.json \
        interview-questions-runner/phase4-rewrite/batch-04-checkpoint.md \
        interview-questions-runner/phase4-rewrite/tracking.json \
        cloud-labs/lab-095-interview-drill-mcq/questions/interview-1.json \
        cloud-labs/lab-095-interview-drill-mcq/questions/interview-2.json \
        cloud-labs/lab-095-interview-drill-mcq/questions/interview-3.json
git commit -m "phase4: batch T1.4 — reframe 22 Terraform + Linux D-only MCQ stems"
```

---

## Task 7: Batch T1.5 — Docker + Git Tier 1 (21 stem reframes)

**Identical procedure to Task 3.** Slice: 13 Docker + 8 Git D-only MCQs.

- [ ] Step 1: Identify 13 Docker + 8 Git D-only MCQ IDs.
- [ ] Step 2: Reframe stems. Docker-specific consideration: layer caching, multi-stage builds, COPY vs ADD, ENTRYPOINT vs CMD. Git-specific consideration: rebase vs merge, reset variants, detached HEAD — strong 6-month-candidate confusion candidates.
- [ ] Step 3: Write `batch-05-tier1-docker-git.json`.
- [ ] Step 4: Apply.
- [ ] Step 5: Validate.
- [ ] Step 6: Drift check.
- [ ] Step 7: Update tracking.json. **Compute final Tier 1 dropout rate** — flag in checkpoint if it materially differs from the 20–30% estimate.
- [ ] Step 8: Write `batch-05-checkpoint.md`. Include two sections: (a) **"Tier 1 cumulative"** — N batches done, X total dropouts, Y% rate, [matches | undershoots | overshoots] the 20-30% estimate; (b) **"Recall-stem drop-outs (T1.4 + T1.5 combined)"** — list per-batch and combined counts. **If combined T1.4+T1.5 recall-stem drop-outs exceed ~40% of the combined slice (≥17 of 43), flag prominently with a recommendation to revisit the intentional-recall exception** before any further rewrite work.
- [ ] Step 9: Surface to Stephen — GATE.
- [ ] Step 10: Commit.

```bash
git add interview-questions-runner/phase4-rewrite/batch-05-tier1-docker-git.json \
        interview-questions-runner/phase4-rewrite/batch-05-checkpoint.md \
        interview-questions-runner/phase4-rewrite/tracking.json \
        cloud-labs/lab-095-interview-drill-mcq/questions/interview-1.json \
        cloud-labs/lab-095-interview-drill-mcq/questions/interview-2.json \
        cloud-labs/lab-095-interview-drill-mcq/questions/interview-3.json
git commit -m "phase4: batch T1.5 — reframe 21 Docker + Git D-only MCQ stems; close Tier 1"
```

---

## Task 8: Batch T2.1 — A-only distractor swaps (11 MCQs)

**Files:**
- Create: `interview-questions-runner/phase4-rewrite/batch-06-tier2.json`
- Create: `interview-questions-runner/phase4-rewrite/batch-06-checkpoint.md`
- Modify: bank files; `tracking.json`

**Tier 2 procedure:**

For each MCQ in the slice (11 A-only flagged MCQs across AWS 4, CI/CD 4, K8s 2, Git 1):

1. Read current MCQ. Identify which distractor was flagged by `suspect-distractors.json` (correlate IDs).
2. Apply the **6-month-candidate test** to the flagged distractor — confirm it's actually a fabrication before replacing (the suspect script is heuristic; a small number may be false positives, e.g. genuine deprecation facts).
3. If confirmed fabrication: research a real misconception for the source's concept. The other distractors in the same MCQ already pass; they constrain the replacement (don't duplicate their pattern). Write the replacement.
4. Apply the **6-month-candidate test to the new distractor** — record the `real_misconception` justification.
5. Update the explanation: the sentence that addressed the old distractor now needs to address the new one.
6. Record before/after in batch JSON with `distractor_self_check` flagged `touched: true` on the swapped key.

If the suspect distractor turns out to be a real misconception on review (false positive), record the MCQ as `dropped_to_tier3: false` AND **no change** — set `change_summary: "no change — suspect distractor verified as real misconception on review"` and explain in the self-check record. The MCQ is removed from the flagged set by this verification.

- [ ] **Step 0: Re-anchor on the pilot voice**

Before any authoring, re-read `interview-questions-runner/phase2-pilot/pilot.json` end-to-end. Tier 2's distractor swaps must match the pilot's per-distractor reasoning — each replacement encodes a specific real misconception, and the explanation addresses why it fails. Re-anchor even if the pilot was re-read at the start of Tier 1.

- [ ] **Step 1: Identify the 11 A-only MCQ IDs and cross-reference suspect-distractors.json**

```bash
cd /c/Users/naylo/Labs/cloud-engineer-labs
python -c "
import json
flagged = json.load(open('interview-questions-runner/phase3-audit/flagged-mcqs.json'))
suspect = json.load(open('interview-questions-runner/phase3-audit/suspect-distractors.json'))
a_only = [x['id'] for x in flagged if x['flags'] == ['A_fabricated']]
print('A-only IDs:', a_only)
# Map suspect rows by id
suspect_by_id = {}
for s in suspect:
    suspect_by_id.setdefault(s['id'], []).append(s)
for mid in a_only:
    print(mid, '->', suspect_by_id.get(mid, 'no suspect entry'))
"
```

Expected: 11 IDs printed, each with the corresponding suspect-distractor rows (which distractor key was flagged and the pattern).

- [ ] **Step 2: For each MCQ, perform the Tier 2 procedure.** Write all rewrites into `batch-06-tier2.json`.
- [ ] **Step 3: Apply rewrites back into bank files** — same script as Task 3 step 4, with `batch-06-tier2.json`.
- [ ] **Step 4: Validate** all three bank files.
- [ ] **Step 5: Drift check** — `python interview-questions-runner/scripts/check_drift.py interview-questions-runner/phase4-rewrite/batch-06-tier2.json`. Expected PASS — Tier 2 doesn't touch stems, so D-flag regressions are unlikely; the only drift risk is the new distractor itself triggering a suspect-distractor pattern, which `audit.py` doesn't check (only `audit_suspect.py` does). **Additional Tier 2 check: also run `audit_suspect.py` and compare the new suspect-distractors.json against the prior one to confirm we haven't introduced new suspect distractors.**

```bash
python interview-questions-runner/scripts/audit_suspect.py
python -c "
import json
new = json.load(open('interview-questions-runner/phase3-audit/suspect-distractors.json'))
batch = json.load(open('interview-questions-runner/phase4-rewrite/batch-06-tier2.json'))
touched = {r['mcq_id'] for r in batch['rewrites']}
new_for_touched = [s for s in new if s['id'] in touched]
print(json.dumps(new_for_touched, indent=2))
print('count:', len(new_for_touched))
"
```

Any new suspect entries on the touched IDs → flag as a fabrication self-check miss and rework before checkpoint.

- [ ] **Step 6: Update tracking.json.** Set `tier2_fabrications_caught` to the count of distractors actually rewritten (vs. count flagged but verified as real).
- [ ] **Step 7: Write `batch-06-checkpoint.md`.** Sample format: 3-4 MCQs from the batch. Include any verified-as-real-misconception non-changes — these are particularly interesting for Stephen since they refine the rubric.
- [ ] **Step 8: Surface to Stephen — GATE.**
- [ ] **Step 9: Commit.**

```bash
git add interview-questions-runner/phase4-rewrite/batch-06-tier2.json \
        interview-questions-runner/phase4-rewrite/batch-06-checkpoint.md \
        interview-questions-runner/phase4-rewrite/tracking.json \
        cloud-labs/lab-095-interview-drill-mcq/questions/interview-1.json \
        cloud-labs/lab-095-interview-drill-mcq/questions/interview-2.json \
        cloud-labs/lab-095-interview-drill-mcq/questions/interview-3.json
git commit -m "phase4: batch T2.1 — replace 11 A-only fabricated distractors (or verify as real)"
```

---

## Task 9: Batch T3.1 — Structural rewrites part 1 (13 MCQs)

**Files:**
- Create: `interview-questions-runner/phase4-rewrite/batch-07-tier3-part1.json`
- Create: `interview-questions-runner/phase4-rewrite/batch-07-checkpoint.md`
- Modify: bank files; `tracking.json`

**Tier 3 procedure:**

For each MCQ in the slice (AWS 4, K8s 5, CI/CD 4 — the first 13 of 21):

1. Read current MCQ. Note the flag combination (B_scrambles + D_match_style; C_never_correct; A+D; etc.) — this dictates the rewrite shape.
2. Read the source from `Interview-Prep-Combined.md`. Identify the actual concept the source teaches.
3. Identify the other MCQ from the same `source_id` (each source has two MCQs). Confirm the other MCQ tests a distinct facet — the rewrite must not collide with it.
4. **Author the MCQ from scratch** against the rubric: scenario stem, 4 options with at least 2 of the 5 distractor patterns from brief §4.2 represented, explanation that addresses why each distractor fails. The pilot.json is the voice; Appendix A is the bar.
5. Apply the **6-month-candidate test to all 4 options** (correct + 3 distractors). Record the per-option self-check.
6. Length-check: explanation ≤130 words (validate script's grace allowance).

Drop-out is unusual at Tier 3 — these are full rewrites, you control the shape. If you can't produce a clean MCQ for a source (e.g., the source's concept doesn't decompose into a clean MCQ), record `dropped_to_tier3: false, change_summary: "source concept does not decompose into rubric-compliant MCQ; recommend dropping this MCQ from the bank"` and surface for Stephen's decision. Don't force a bad MCQ in.

- [ ] **Step 0: Re-anchor on the pilot voice**

Before any authoring, re-read `interview-questions-runner/phase2-pilot/pilot.json` end-to-end. Tier 3 produces full rewrites; the pilot is the closest analogue to what each Tier 3 MCQ should look like. Re-anchor even if the pilot was re-read at the start of earlier tiers.

- [ ] **Step 1: Identify the 13 Tier 3 part 1 IDs (AWS + K8s + CI/CD structural / multi-flag)**

```bash
cd /c/Users/naylo/Labs/cloud-engineer-labs
python -c "
import json
data = json.load(open('interview-questions-runner/phase3-audit/flagged-mcqs.json'))
d_only = {x['id'] for x in data if x['flags'] == ['D_definition']}
a_only = {x['id'] for x in data if x['flags'] == ['A_fabricated']}
tier3 = [x for x in data if x['id'] not in d_only and x['id'] not in a_only]
part1 = [x for x in tier3 if x['domain'] in ('aws', 'kubernetes', 'cicd')]
print('count:', len(part1))
for x in part1: print(x['id'], x['domain'], x['flags'])
"
```

Expected: 13 IDs.

- [ ] **Step 2: For each, perform the Tier 3 procedure. Write `batch-07-tier3-part1.json`.**
- [ ] **Step 3: Apply rewrites back into bank files.**
- [ ] **Step 4: Validate.**
- [ ] **Step 5: Drift check.** Expected PASS — Tier 3 fully reauthors so structural and definition flags should clear.
- [ ] **Step 6: Run audit_suspect.py and check for new suspect entries on touched IDs (same approach as Task 8 step 5).**
- [ ] **Step 7: Update tracking.json.**
- [ ] **Step 8: Write `batch-07-checkpoint.md`.** Sample format: 3-4 MCQs, **mandatorily including any "source doesn't decompose" candidates** for Stephen's decision.
- [ ] **Step 9: Surface to Stephen — GATE.**
- [ ] **Step 10: Commit.**

```bash
git add interview-questions-runner/phase4-rewrite/batch-07-tier3-part1.json \
        interview-questions-runner/phase4-rewrite/batch-07-checkpoint.md \
        interview-questions-runner/phase4-rewrite/tracking.json \
        cloud-labs/lab-095-interview-drill-mcq/questions/interview-1.json \
        cloud-labs/lab-095-interview-drill-mcq/questions/interview-2.json \
        cloud-labs/lab-095-interview-drill-mcq/questions/interview-3.json
git commit -m "phase4: batch T3.1 — reauthor 13 structural-fail MCQs (AWS/K8s/CI/CD)"
```

---

## Task 10: Batch T3.2 — Structural rewrites part 2 (8 MCQs) + Tier 1 drop-outs

**Files:**
- Create: `interview-questions-runner/phase4-rewrite/batch-08-tier3-part2.json`
- Create: `interview-questions-runner/phase4-rewrite/batch-08-checkpoint.md`
- Modify: bank files; `tracking.json`

**Slice:** 8 remaining Tier 3 structural MCQs (TF 4, Docker 3, Linux 1) **plus all Tier 1 drop-outs collected during Tasks 3–7**.

- [ ] **Step 1: Identify the 8 remaining T3 IDs + collect drop-out IDs from tracking.json**

```bash
python -c "
import json
data = json.load(open('interview-questions-runner/phase3-audit/flagged-mcqs.json'))
d_only = {x['id'] for x in data if x['flags'] == ['D_definition']}
a_only = {x['id'] for x in data if x['flags'] == ['A_fabricated']}
tier3 = [x for x in data if x['id'] not in d_only and x['id'] not in a_only]
part2 = [x for x in tier3 if x['domain'] in ('terraform', 'docker', 'linux')]
print('t3 part2 count:', len(part2))
for x in part2: print(x['id'], x['domain'], x['flags'])

tracking = json.load(open('interview-questions-runner/phase4-rewrite/tracking.json'))
dropouts = []
for b in tracking['batches']:
    dropouts.extend(b.get('drop_out_ids', []))
print('dropouts to absorb:', dropouts)
"
```

- [ ] **Step 2: For each, perform the Tier 3 procedure. Write `batch-08-tier3-part2.json`.** Mark each rewrite with its origin (`origin: "T3_structural"` or `origin: "T1_dropout_from_T1.X"`) for traceability.
- [ ] **Step 3: Apply rewrites back into bank files.**
- [ ] **Step 4: Validate.**
- [ ] **Step 5: Drift check.**
- [ ] **Step 6: audit_suspect.py check on touched IDs.**
- [ ] **Step 7: Update tracking.json.**
- [ ] **Step 8: Write `batch-08-checkpoint.md`.**
- [ ] **Step 9: Surface to Stephen — GATE.**
- [ ] **Step 10: Commit.**

```bash
git add interview-questions-runner/phase4-rewrite/batch-08-tier3-part2.json \
        interview-questions-runner/phase4-rewrite/batch-08-checkpoint.md \
        interview-questions-runner/phase4-rewrite/tracking.json \
        cloud-labs/lab-095-interview-drill-mcq/questions/interview-1.json \
        cloud-labs/lab-095-interview-drill-mcq/questions/interview-2.json \
        cloud-labs/lab-095-interview-drill-mcq/questions/interview-3.json
git commit -m "phase4: batch T3.2 — reauthor remaining structural MCQs + Tier 1 dropouts"
```

---

## Task 11: Full re-audit, summary report, and PR readiness

**Files:**
- Create: `interview-questions-runner/phase4-rewrite/final-report.md`
- Modify: `tracking.json` (final totals)

- [ ] **Step 1: Run the full audit suite from clean state**

```bash
cd /c/Users/naylo/Labs/cloud-engineer-labs
python interview-questions-runner/scripts/audit.py
python interview-questions-runner/scripts/audit_suspect.py
python interview-questions-runner/scripts/validate_mcqs.py cloud-labs/lab-095-interview-drill-mcq/questions/interview-1.json
python interview-questions-runner/scripts/validate_mcqs.py cloud-labs/lab-095-interview-drill-mcq/questions/interview-2.json
python interview-questions-runner/scripts/validate_mcqs.py cloud-labs/lab-095-interview-drill-mcq/questions/interview-3.json
```

Expected: audit.py reports `MCQs with any flag (C or D): N` where N is small (only intentional-recall MCQs, if any survived). audit_suspect.py reports a small list with reasoned non-fabrication tags. validate exits 0 on all three banks.

- [ ] **Step 2: Compute final bank statistics**

```bash
python -c "
import json
from collections import Counter
for b in (1,2,3):
    mcqs = json.load(open(f'cloud-labs/lab-095-interview-drill-mcq/questions/interview-{b}.json'))
    print(f'Bank {b}: {len(mcqs)} MCQs, domains:', dict(Counter(m['domain'] for m in mcqs)))
"
```

Confirm bank sizes are unchanged (~69 each) and domain distribution matches `Interview-Drill-Runner.md` §3.1.

- [ ] **Step 3: Write final-report.md**

```markdown
# Phase 4 — final report

## Headline

- Started: 126 / 208 MCQs flagged (61%)
- Ended: N / 208 flagged (X%) — [resolved | remaining intentional-recall | other]
- Tier 1 actual dropout rate: X% (vs. 20-30% estimate)
- Tier 2 fabrications confirmed and replaced: N of 11
- Tier 2 suspects verified as real misconceptions (no change): N of 11
- Tier 3 full rewrites: N
- Source MCQs dropped from bank (per Stephen's decision): N — list IDs

## Per-batch summary

(Table from tracking.json: batch_id, tier, slice, completed, dropouts, status.)

## Tightened rubric — was it sufficient?

Honest assessment: did the operationalised 6-month-candidate test actually prevent fabrications during the rewrite? Cite specific examples from the checkpoints where it caught something / let something through. Recommend any further rubric changes for future banks.

## Suggested next steps

- Stephen spot-check ~10 of the rewritten MCQs end-to-end
- Update `phase3-audit/README.md` to reflect "audit acted on by Phase 4 — see phase4-rewrite/final-report.md"
- PR is ready to merge
```

- [ ] **Step 4: Update CHALLENGE.md or SOLUTION.md in `cloud-labs/lab-095-interview-drill-mcq/` if any author-facing notes need refreshing** — likely a one-line update at most ("MCQs revised in Phase 4; see interview-questions-runner/phase4-rewrite/final-report.md").

- [ ] **Step 5: Surface final-report.md to Stephen.**

- [ ] **Step 6: Commit and offer PR update.**

```bash
git add interview-questions-runner/phase4-rewrite/final-report.md \
        interview-questions-runner/phase4-rewrite/tracking.json
git commit -m "phase4: final re-audit, summary report, ready for review"
```

Then offer: "PR #1 (feat/lab-interview-drill-phase1) is ready for re-review. Want me to push and update the PR description?"

---

## Notes on execution discipline

1. **Never claim "done" without running the drift check.** The user explicitly mechanised this requirement; the checkpoint format puts the drift result first for that reason.
2. **Drift FAIL means the checkpoint shows ONLY the drift.** If `check_drift.py` exits non-zero, the batch checkpoint markdown contains the drift result, the touched IDs that still flag, and any regressions — nothing else. Fix-and-retry happens locally before human review. Don't include samples, self-assessment, false-positive verifications, or "decision requested" until drift PASSes.
3. **The 6-month-candidate test is not optional.** It applies to every distractor authored or rewritten. The self-check record format in batch JSON is the audit trail.
4. **Drop-outs are signal, not failure.** Tier 1 → Tier 3 drop-out is the rubric working. Track them; don't smooth them over by force-fitting a stem reframe.
5. **Source for content: `Interview-Prep-Combined.md` in the parent repo.** Task 0 Step 1 verifies it's available before any tier batch starts.
6. **One MCQ change per source bank entry.** Match on `id`. Never re-order or re-key the bank arrays.
7. **Report session context at every checkpoint, recommend handoff at ~65%.** Long sessions degrade authoring quality; the checkpoint template has a Session context status section. If the agent estimates context usage at or above 65%, the checkpoint recommends a fresh session before the next batch; tracking.json is the handoff state.
