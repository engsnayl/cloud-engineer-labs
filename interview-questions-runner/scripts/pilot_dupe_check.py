"""Pre-flight pilot-duplicate check (build into every batch).

Compares each bank MCQ against the pilot exemplar of the same id for
byte-identity on question + options + explanation. A byte-identical match
means the bank MCQ already IS the bar — it should auto-clear as a heuristic
false positive rather than be reframed.

Usage:
  python interview-questions-runner/scripts/pilot_dupe_check.py            # scan all banks
  python interview-questions-runner/scripts/pilot_dupe_check.py id1 id2..  # restrict to ids

Exit 0 always (informational). Prints byte-identical ids and whether each is
currently in flagged-mcqs.json.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PILOT = ROOT / "interview-questions-runner/phase2-pilot/pilot.json"
QDIR = ROOT / "cloud-labs/lab-095-interview-drill-mcq/questions"
FLAGGED = ROOT / "interview-questions-runner/phase3-audit/flagged-mcqs.json"

CMP_KEYS = ("question", "options", "explanation")


def core(m):
    return {k: m.get(k) for k in CMP_KEYS}


def main():
    restrict = set(sys.argv[1:])
    pilot = {m["id"]: m for m in json.loads(PILOT.read_text(encoding="utf-8"))}
    flagged_ids = {r["id"] for r in json.loads(FLAGGED.read_text(encoding="utf-8"))}

    bank = {}
    for b in (1, 2, 3):
        for m in json.loads((QDIR / f"interview-{b}.json").read_text(encoding="utf-8")):
            bank[m["id"]] = m

    matches = []
    for pid, pm in pilot.items():
        if restrict and pid not in restrict:
            continue
        bm = bank.get(pid)
        if bm and core(bm) == core(pm):
            matches.append((pid, pid in flagged_ids))

    print(f"Pilot exemplars: {len(pilot)} | scanned: {'restricted '+str(sorted(restrict)) if restrict else 'all banks'}")
    print(f"Byte-identical bank<->pilot matches: {len(matches)}")
    for pid, is_flagged in sorted(matches):
        tag = "FLAGGED -> auto-clear as FP" if is_flagged else "not flagged (no action)"
        print(f"  {pid:20s} {tag}")


if __name__ == "__main__":
    main()
