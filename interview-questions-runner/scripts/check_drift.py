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

    still_flagged = []
    for mid in sorted(touched_ids):
        row = new_by_id.get(mid)
        if row is None:
            still_flagged.append((mid, ["MISSING_FROM_AUDIT"]))
        elif row["flags"]:
            still_flagged.append((mid, row["flags"]))

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
