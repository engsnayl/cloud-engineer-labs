"""Extract a curated spot-check sample of 18 MCQs across all 3 banks
per Stephen's review brief:

  Per-bank: 6 each (B1=6, B2=6, B3=6 = 18)
  Per-domain: 4 TF, 3 K8s, 3 CI/CD, 2 AWS, 2 Docker, 2 Linux, 2 Git
    (Note: stated brief said 3 TF / 3 AWS but also "at least 4 TF",
     so TF was bumped to 4 at AWS's expense.)
  Priority: 6 critical, 10 high, 2 medium (no low)
  Provenance: 14 of 18 are from batches that tripped the 'correct is
    longest' set-level warning (batches 2, 3, 4, 6, 7, 9) so the
    rebalances can be reviewed alongside fresh content
"""

import json
from pathlib import Path

QUESTIONS_DIR = Path("cloud-labs/lab-095-interview-drill-mcq/questions")
OUT = Path("interview-questions-runner/phase3-spotcheck.json")

PICKS = [
    # Bank 1 (6 MCQs)
    "k8s-023-mcq-1",      # critical, autoscaler axes (batch 4 rebalanced)
    "cicd-010-mcq-1",     # critical, GHA hierarchy (batch 5 clean)
    "tf-005-mcq-1",       # high, why workspaces don't fit envs (batch 7 rebalanced)
    "tf-013-mcq-1",       # high, first step on unexpected diff (batch 7 rebalanced)
    "linux-002-mcq-1",    # high, SIGTERM vs SIGKILL (batch 9 rebalanced)
    "git-001-mcq-1",      # high, merge vs rebase reason (batch 9 rebalanced)
    # Bank 2 (6 MCQs)
    "k8s-001-mcq-2",      # critical, when to handcraft a ReplicaSet (batch 3 rebalanced)
    "cicd-031-mcq-1",     # high, expand-contract migration (batch 6 rebalanced)
    "tf-008-mcq-1",       # medium, terraform refresh (batch 7 rebalanced)
    "aws-032-mcq-1",      # critical, app slow first signal (batch 2 rebalanced)
    "docker-002-mcq-2",   # critical, non-root user (batch 8 absolute removed)
    "linux-003-mcq-1",    # high, systemd unit types (batch 9 rebalanced)
    # Bank 3 (6 MCQs)
    "k8s-051-mcq-2",      # high, CPU throttling diagnosis (batch 4 rebalanced)
    "cicd-050-mcq-2",     # critical, what isn't a flake source (batch 6 rebalanced)
    "tf-009-mcq-2",       # high, state lock contention (batch 7 rebalanced)
    "aws-005-mcq-2",      # high, Multi-AZ misused for read scaling (batch 1)
    "docker-009-mcq-2",   # high, ECR lifecycle + tag immutability (batch 8)
    "git-006-mcq-2",      # medium, secret-in-history recovery (batch 9 rebalanced)
]


def main():
    by_id: dict[str, dict] = {}
    for b in (1, 2, 3):
        path = QUESTIONS_DIR / f"interview-{b}.json"
        for mcq in json.loads(path.read_text(encoding="utf-8")):
            by_id[mcq["id"]] = {**mcq, "bank": b}

    missing = [pid for pid in PICKS if pid not in by_id]
    if missing:
        raise SystemExit(f"missing: {missing}")

    sample = [by_id[pid] for pid in PICKS]

    # Summary
    from collections import Counter

    by_bank = Counter(m["bank"] for m in sample)
    by_dom = Counter(m["domain"] for m in sample)
    by_prio = Counter(m["priority"] for m in sample)
    print(f"Selected: {len(sample)} MCQs")
    print(f"By bank: {dict(sorted(by_bank.items()))}")
    print(f"By domain: {dict(sorted(by_dom.items()))}")
    print(f"By priority: {dict(sorted(by_prio.items()))}")

    OUT.write_text(json.dumps(sample, indent=2), encoding="utf-8")
    print(f"Wrote {OUT}")


if __name__ == "__main__":
    main()
