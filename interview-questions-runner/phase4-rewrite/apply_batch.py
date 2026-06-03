"""Generic batch apply. Usage: python apply_batch.py <batch.json>
Writes `after` for completed rewrites, `before` (original) for dropped/cleared.
Matches existing bank format (ensure_ascii=True, indent=2, no trailing newline)."""
import json, sys
from pathlib import Path

ROOT = Path("C:/Users/naylo/Labs/cloud-engineer-labs")
batch = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
qdir = ROOT / "cloud-labs/lab-095-interview-drill-mcq/questions"

intended = {r["mcq_id"]: (r["before"] if r.get("dropped_to_tier3") else r["after"])
            for r in batch["rewrites"]}
count = 0
for b in (1, 2, 3):
    p = qdir / f"interview-{b}.json"
    mcqs = json.loads(p.read_text(encoding="utf-8"))
    for m in mcqs:
        if m["id"] in intended:
            tgt = intended[m["id"]]
            m["question"], m["options"], m["explanation"] = tgt["question"], tgt["options"], tgt["explanation"]
            count += 1
    p.write_text(json.dumps(mcqs, indent=2), encoding="utf-8")
print(f"Synced {count} MCQs across bank files for {batch['batch_id']}")
