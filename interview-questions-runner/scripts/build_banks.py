"""Merge all pilot + appendix-A + batch files into 3 bank files at the
final lab location. Each MCQ's `bank` field tells us which file to put it in.
"""

import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path("interview-questions-runner")
PILOT = ROOT / "phase2-pilot/pilot.json"
APPENDIX = ROOT / "phase3-batches/appendix-a.json"
BATCH_GLOB = sorted((ROOT / "phase3-batches").glob("batch-*.json"))

OUT_DIR = Path("cloud-labs/lab-095-interview-drill-mcq/questions")


def main():
    all_mcqs = []
    sources = [PILOT, APPENDIX] + BATCH_GLOB
    for src in sources:
        data = json.loads(src.read_text(encoding="utf-8"))
        print(f"  {src.name}: {len(data)} MCQs", file=sys.stderr)
        all_mcqs.extend(data)

    print(f"\nTotal MCQs: {len(all_mcqs)}", file=sys.stderr)

    # Validate uniqueness
    ids = [m["id"] for m in all_mcqs]
    dupes = [k for k, v in Counter(ids).items() if v > 1]
    if dupes:
        print(f"ERROR: duplicate MCQ ids: {dupes}", file=sys.stderr)
        sys.exit(1)

    # Partition by bank
    banks: dict[int, list[dict]] = {1: [], 2: [], 3: []}
    for m in all_mcqs:
        bank = m["bank"]
        # Drop the bank field from the production output (file location implies bank).
        mcq_out = {k: v for k, v in m.items() if k != "bank"}
        banks[bank].append(mcq_out)

    for b, items in banks.items():
        # Sort within each bank by id for stable diffing.
        items.sort(key=lambda m: m["id"])
        print(f"\nBank {b}: {len(items)} MCQs", file=sys.stderr)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for b, items in banks.items():
        out_path = OUT_DIR / f"interview-{b}.json"
        out_path.write_text(json.dumps(items, indent=2), encoding="utf-8")
        print(f"  wrote {out_path}", file=sys.stderr)

    # Summary by domain per bank
    print("\nDomain mix per bank:", file=sys.stderr)
    for b, items in banks.items():
        by_dom = Counter(m["domain"] for m in items)
        print(f"  Bank {b}: {dict(sorted(by_dom.items()))}", file=sys.stderr)


if __name__ == "__main__":
    main()
