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

    picked = []
    for d in domains:
        if len(picked) == 6:
            break
        pool = by_domain[d]
        if not pool:
            continue
        picked.append(rng.choice(pool))

    if len(picked) < 6:
        remaining = [
            m for d in domains for m in by_domain[d]
            if m["id"] not in {p["id"] for p in picked}
        ]
        rng.shuffle(remaining)
        picked.extend(remaining[: 6 - len(picked)])

    OUT.write_text(json.dumps(picked, indent=2), encoding="utf-8")
    print(f"Wrote {len(picked)} control-sample MCQs to {OUT}")
    for m in picked:
        print(f"  {m['id']:25s} bank={m['bank']} domain={m['domain']}")


if __name__ == "__main__":
    main()
