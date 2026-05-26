"""Flag suspect distractors that match patterns commonly associated with
fabrication (Stephen's redline category A). Each pattern is a heuristic
that surfaces candidates for manual verification — not all matches are
fabrications, and the script also won't catch all fabrications.

Patterns considered:
  - Deprecation/removal claims with version numbers
  - 'Automatically' / 'implicit' / 'built-in' + specific feature
  - Specific quantitative claims (%, hours, ms) that are unusual
  - Fictional-sounding named features
  - Apparent anti-patterns no candidate would propose
"""

import json
import re
from pathlib import Path

QUESTIONS_DIR = Path("cloud-labs/lab-095-interview-drill-mcq/questions")
OUT = Path("interview-questions-runner/phase3-audit/suspect-distractors.json")

SUSPECT_PATTERNS = [
    # Deprecation / removal claims with version numbers
    (r"\b(deprecated|removed)\s+(in|since|from)\s+(version\s+)?[0-9]", "version-deprecation"),
    (r"\b(removed)\s+(in|since|from)\s+(Terraform|Kubernetes|EKS|Docker|GitHub Actions)\s+[0-9]", "platform-removal"),
    (r"\bno longer (works|supports?|available)\s+(in|with|after)\s+", "removed-feature"),
    # Automatic / implicit claims
    (r"\b(automatic|automatically|implicit|implicitly|built[- ]in|natively)\s+\w+", "auto-implicit"),
    # Quantitative claims
    (r"\b\d+\s*(min|minute|hour|hr|ms|millisecond|second|sec)s?\b", "specific-duration"),
    (r"\b\d+%\b", "specific-percent"),
    (r"\b\d+x\b", "specific-multiplier"),
    # Surprising fact claims
    (r"\b(charges?\s+less|free of charge|no\s+cost|billing optimisation|billing optimization)\b", "billing-claim"),
    # Plausible-sounding made-up feature names
    (r"`?--[a-z]+(-[a-z]+)*=?`?", "specific-flag"),
    (r"`[A-Z_][A-Z_0-9]+`", "specific-env-var"),
    (r"\b[a-z]+\.[a-z]+(\.[a-z]+)+\b", "specific-domain-path"),
]


def scan_distractor(text: str) -> list[str]:
    hits = []
    for pat, label in SUSPECT_PATTERNS:
        if re.search(pat, text):
            hits.append(label)
    return hits


def main():
    out_rows = []
    for b in (1, 2, 3):
        mcqs = json.loads((QUESTIONS_DIR / f"interview-{b}.json").read_text(encoding="utf-8"))
        for m in mcqs:
            for opt_key in ("distractor_1", "distractor_2", "distractor_3"):
                text = m["options"][opt_key]
                hits = scan_distractor(text)
                if hits:
                    out_rows.append(
                        {
                            "id": m["id"],
                            "bank": b,
                            "distractor": opt_key,
                            "text": text,
                            "patterns": hits,
                        }
                    )

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(out_rows, indent=2), encoding="utf-8")
    print(f"Suspect distractors flagged: {len(out_rows)}")
    from collections import Counter
    pat_counts = Counter()
    for r in out_rows:
        for p in r["patterns"]:
            pat_counts[p] += 1
    print(f"By pattern: {dict(pat_counts)}")
    # MCQs with at least one suspect distractor
    mcq_ids = {r["id"] for r in out_rows}
    print(f"Distinct MCQs with suspect distractor: {len(mcq_ids)}")


if __name__ == "__main__":
    main()
