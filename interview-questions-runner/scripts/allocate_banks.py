"""Phase 1 allocator: assign each source's 2 MCQs to 2 of the 3 banks.

Strategy:
- Drop the 6 behavioural sources (beh-*).
- Per domain, set bank capacity totals matching brief Section 3 (sum = 2N).
- Each source contributes 1 MCQ to two different banks (pair type ∈ {(1,2),(1,3),(2,3)}).
- Pair-type quotas are solved from bank capacities so totals match exactly.
- Critical/high priority sources are spread across pair types so every bank
  contains a representative slice of high-priority material.
"""

import json
from collections import Counter, defaultdict
from pathlib import Path

SRC = Path("interview-questions-runner/phase1/sources.json")
OUT = Path("interview-questions-runner/phase1/allocation.json")

# Per-domain bank capacities (sum = 2*N). Domain order: keep stable for output.
BANK_CAPACITY = {
    "aws":        (19, 19, 18),
    "kubernetes": (15, 14, 15),
    "cicd":       (12, 12, 12),
    "terraform":  (8,  9,  9),
    "docker":     (7,  6,  7),
    "linux":      (5,  5,  4),
    "git":        (4,  4,  4),
}

EXCLUDED_DOMAIN = "behavioural"

PRIORITY_RANK = {"critical": 0, "high": 1, "medium": 2, "low": 3}

PAIR_TYPES = [(1, 2), (1, 3), (2, 3)]


def pair_quotas(cap):
    """Given (c1, c2, c3) bank capacities for a domain, solve pair counts."""
    c1, c2, c3 = cap
    n = (c1 + c2 + c3) // 2
    # p12 + p13 = c1; p12 + p23 = c2; p13 + p23 = c3
    p12 = n - c3
    p13 = c1 - p12
    p23 = c2 - p12
    assert p12 >= 0 and p13 >= 0 and p23 >= 0, (cap, p12, p13, p23)
    assert p12 + p13 + p23 == n
    assert p12 + p13 == c1 and p12 + p23 == c2 and p13 + p23 == c3
    return {"(1,2)": p12, "(1,3)": p13, "(2,3)": p23}


def allocate_domain(sources, cap):
    """Assign each source in this domain to a pair type, respecting quotas
    and spreading critical/high priority across pair types."""
    quotas = pair_quotas(cap)
    remaining = dict(quotas)
    # Sort sources stable by priority, then id (deterministic).
    sources = sorted(
        sources,
        key=lambda q: (PRIORITY_RANK.get(q["priority"], 9), q["id"]),
    )
    assignments = []
    # For each priority tier, cycle pair types in round-robin so the tier
    # is spread across all three banks.
    by_priority = defaultdict(list)
    for q in sources:
        by_priority[q["priority"]].append(q)
    for prio in ["critical", "high", "medium", "low"]:
        bucket = by_priority.get(prio, [])
        # Round-robin in PAIR_TYPES order, but skip when quota is exhausted.
        cursor = 0
        for q in bucket:
            # Find next pair type with quota > 0.
            chosen = None
            for _ in range(len(PAIR_TYPES)):
                pt = PAIR_TYPES[cursor % len(PAIR_TYPES)]
                cursor += 1
                key = f"({pt[0]},{pt[1]})"
                if remaining[key] > 0:
                    chosen = pt
                    remaining[key] -= 1
                    break
            assert chosen is not None, (prio, q["id"], remaining)
            assignments.append((q, chosen))
    # Sanity: all quotas exhausted.
    assert all(v == 0 for v in remaining.values()), remaining
    return assignments


def main():
    sources = json.loads(SRC.read_text(encoding="utf-8"))
    sources = [s for s in sources if s["domain_dir"] != EXCLUDED_DOMAIN]
    by_domain = defaultdict(list)
    for s in sources:
        by_domain[s["domain_dir"]].append(s)

    output_rows = []
    summary = {
        "bank_totals": {1: 0, 2: 0, 3: 0},
        "domain_bank_totals": {},
        "priority_bank_totals": {1: Counter(), 2: Counter(), 3: Counter()},
        "domain_pair_quotas": {},
    }

    for domain, cap in BANK_CAPACITY.items():
        domain_sources = by_domain.get(domain, [])
        summary["domain_pair_quotas"][domain] = pair_quotas(cap)
        assignments = allocate_domain(domain_sources, cap)
        d_bank_count = Counter()
        for q, (b_a, b_b) in assignments:
            output_rows.append(
                {
                    "id": q["id"],
                    "domain": domain,
                    "subdomain": q.get("subdomain"),
                    "priority": q["priority"],
                    "difficulty": q["difficulty"],
                    "stem": q["stem"],
                    "concepts": q["concepts"],
                    "mcq_1_bank": b_a,
                    "mcq_2_bank": b_b,
                }
            )
            d_bank_count[b_a] += 1
            d_bank_count[b_b] += 1
            summary["bank_totals"][b_a] += 1
            summary["bank_totals"][b_b] += 1
            summary["priority_bank_totals"][b_a][q["priority"]] += 1
            summary["priority_bank_totals"][b_b][q["priority"]] += 1
        summary["domain_bank_totals"][domain] = dict(sorted(d_bank_count.items()))
        # Verify against capacity.
        for i, c in enumerate(cap, start=1):
            assert d_bank_count[i] == c, (domain, i, d_bank_count[i], c)

    # Coerce Counters to dicts for JSON.
    summary["priority_bank_totals"] = {
        k: dict(v) for k, v in summary["priority_bank_totals"].items()
    }
    OUT.write_text(
        json.dumps(
            {"allocation": output_rows, "summary": summary},
            indent=2,
            default=str,
        ),
        encoding="utf-8",
    )
    # Human summary
    print("Bank totals:", summary["bank_totals"])
    print("Per-domain per-bank:")
    for d, v in summary["domain_bank_totals"].items():
        print(f"  {d}: {v}")
    print("Per-bank priority mix:")
    for b, v in summary["priority_bank_totals"].items():
        print(f"  bank {b}: {v}")


if __name__ == "__main__":
    main()
