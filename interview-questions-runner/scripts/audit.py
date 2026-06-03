"""Heuristic audit pass over all 208 MCQs. Flags:

C: 'which is NOT' or 'never' / 'essentially never' as correct option
D: definition-match stems (no scenario, pure recall)

Output is a draft that's then merged with a manual review for
categories A (fabricated distractors) and B (scrambles in match-style).
"""

import json
import re
from pathlib import Path

QUESTIONS_DIR = Path("cloud-labs/lab-095-interview-drill-mcq/questions")
OUT = Path("interview-questions-runner/phase3-audit/draft-audit.json")

SCENARIO_MARKERS = [
    r"\bA\s+(pod|user|service|team|developer|deploy|cluster|workflow|container|process)",
    r"\bAn\s+(engineer|application|EC2|EKS|API|ASG|ALB|RDS|S3|EBS|EFS|FSx|IAM|instance)",
    r"\bYour\s+(team|app|application|cluster|company|organisation|organization|deployment|pipeline|service|infrastructure)",
    r"\bYou(\b|'ve|'re|'d|'ll)\s+",
    r"\bTwo\s+(engineers|users|services|pods|developers|teams|workflows)",
    r"\bThree\s+(replicas|pods|services)",
    r"\bDuring\s+a\s+",
    r"\bAfter\s+(deploy|merging|running)",
    r"\bWhen\s+the\s+(application|cluster|deploy|deployment|build|node|pod|workflow)",
    r"\bCloudWatch\s+(alerts|reports|shows)",
    r"\bA\s+(file|container|build|workflow|matrix|service|pipeline|node)",
    r"\bThe\s+(pod|cluster|cluster's|deploy|deployment|build|service|pipeline|workflow)\s+",
    r"^Match\s+",  # match-style mentioned as scenario-like enough to differentiate
]

DEFINITION_MARKERS = [
    r"^What\b",
    r"^Which\b",
    r"^Explain\b",
    r"^Compare\b",
    r"^Define\b",
    r"^In\s+(GitHub|Kubernetes|AWS|Terraform|Docker|Git)\b",
    r"^What's\b",
    r"^How\s+does\s+",
]

NOT_NEVER_STEM = re.compile(r"\b(NOT|which is not)\b")
NEVER_CORRECT = re.compile(r"\b(essentially never|never|none|no\s+\w+\s+exists?)\b", re.IGNORECASE)
MATCH_STYLE_STEM = re.compile(r"\b(Match\b|mapping|hierarchy of|order of|which one of|order is)", re.IGNORECASE)


SCENARIO_LITE = re.compile(
    r"\b(your|you've|you're|you'd|you'll|you\s+(want|need|must|see|notice|observe|configure)|"
    r"Account\s+[A-Z]|tier|in production|"
    r"\d+\s*(replicas?|users?|nodes?|pods?|engineers?|servers?|instances?|containers?|jobs?|services?|workflows?|MCQ|gigabytes?)|"
    r"is\s+(in|stuck|failing|reporting|running|hitting|deploying|updated|added|configured|set|using))",
    re.IGNORECASE,
)


def classify_stem(stem: str) -> str:
    """Return one of: 'scenario', 'definition', 'match'."""
    if MATCH_STYLE_STEM.search(stem):
        return "match"
    for pat in SCENARIO_MARKERS:
        if re.search(pat, stem):
            return "scenario"
    if SCENARIO_LITE.search(stem):
        return "scenario"
    for pat in DEFINITION_MARKERS:
        if re.search(pat, stem):
            return "definition"
    return "definition"


def flag_one(mcq: dict) -> dict:
    flags = []
    notes = []

    # Category C: NOT/never reversal
    if NOT_NEVER_STEM.search(mcq["question"]):
        flags.append("C_not_reversal")
        notes.append("stem uses 'NOT' or 'which is not'")
    correct = mcq["options"]["correct"]
    if re.match(r"\s*(Essentially never|Never|No\b)", correct):
        flags.append("C_never_correct")
        notes.append(f"correct starts with 'Never/No/Essentially never': {correct[:60]}...")

    # Category D: pure definition-match (no scenario in stem)
    stem_type = classify_stem(mcq["question"])
    if stem_type == "definition":
        flags.append("D_definition")
        notes.append("stem reads as recall not scenario")
    elif stem_type == "match":
        flags.append("D_match_style")
        notes.append("match-style stem (high scramble risk)")

    return {
        "id": mcq["id"],
        "domain": mcq["domain"],
        "bank": mcq.get("bank"),
        "stem_type": stem_type,
        "flags": flags,
        "notes": notes,
        "question": mcq["question"][:120],
    }


def main():
    rows = []
    for b in (1, 2, 3):
        mcqs = json.loads((QUESTIONS_DIR / f"interview-{b}.json").read_text(encoding="utf-8"))
        for m in mcqs:
            m["bank"] = b
            rows.append(flag_one(m))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(rows, indent=2), encoding="utf-8")

    # Summary
    from collections import Counter

    cat_counts = Counter()
    for r in rows:
        for f in r["flags"]:
            cat_counts[f] += 1
    flagged_any = [r for r in rows if r["flags"]]
    print(f"Total MCQs: {len(rows)}")
    print(f"Stem types: {Counter(r['stem_type'] for r in rows)}")
    print(f"Category counts: {dict(cat_counts)}")
    print(f"MCQs with any flag (C or D): {len(flagged_any)}")


if __name__ == "__main__":
    main()
