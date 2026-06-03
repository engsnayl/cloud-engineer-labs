"""Programmatic checks against brief Sections 4.3, 4.5, and 5.2.

Runs on any MCQ JSON file (pilot or final banks). Exits non-zero on
hard schema violations. Soft warnings (length balance, possible
absolutes) print to stderr but don't fail.
"""

import json
import re
import sys
from pathlib import Path

REQUIRED_FIELDS = {
    "id",
    "source_id",
    "domain",
    "subdomain",
    "priority",
    "difficulty",
    "question",
    "options",
    "explanation",
}
REQUIRED_OPTION_KEYS = {"correct", "distractor_1", "distractor_2", "distractor_3"}
VALID_DOMAINS = {"aws", "kubernetes", "cicd", "terraform", "docker", "linux", "git"}
VALID_PRIORITIES = {"critical", "high", "medium", "low"}

BANNED_PHRASES = ["all of the above", "none of the above"]
ABSOLUTE_WORDS = re.compile(r"\b(always|never|100%|every single|no exceptions)\b", re.IGNORECASE)

EXPLANATION_WORD_CAP = 130  # brief says ~120, allow a small grace


def word_count(text: str) -> int:
    return len(re.findall(r"\b\w+\b", text))


def validate_one(mcq: dict, errors: list, warnings: list):
    mid = mcq.get("id", "<unknown>")

    missing = REQUIRED_FIELDS - set(mcq.keys())
    if missing:
        errors.append(f"{mid}: missing fields {sorted(missing)}")

    if mcq.get("domain") not in VALID_DOMAINS:
        errors.append(f"{mid}: invalid domain {mcq.get('domain')!r}")
    if mcq.get("priority") not in VALID_PRIORITIES:
        errors.append(f"{mid}: invalid priority {mcq.get('priority')!r}")

    opts = mcq.get("options", {})
    if set(opts.keys()) != REQUIRED_OPTION_KEYS:
        errors.append(f"{mid}: options keys {sorted(opts.keys())} != {sorted(REQUIRED_OPTION_KEYS)}")

    values = [opts.get(k, "") for k in ("correct", "distractor_1", "distractor_2", "distractor_3")]
    # Identical-text checks
    if len(set(values)) != 4:
        errors.append(f"{mid}: option texts are not all distinct")
    if values[0] in values[1:]:
        errors.append(f"{mid}: correct answer text duplicated as a distractor")

    # Banned phrases
    for v in values:
        low = v.lower()
        for banned in BANNED_PHRASES:
            if banned in low:
                errors.append(f"{mid}: banned phrase '{banned}' in an option")

    # Absolutes in distractors only (brief: avoid as giveaways in distractors)
    for k in ("distractor_1", "distractor_2", "distractor_3"):
        text = opts.get(k, "")
        m = ABSOLUTE_WORDS.search(text)
        if m:
            warnings.append(f"{mid}: distractor uses absolute word '{m.group(0)}' -> {k}")

    # Explanation requirements
    expl = mcq.get("explanation", "")
    wc = word_count(expl)
    if wc > EXPLANATION_WORD_CAP:
        errors.append(f"{mid}: explanation is {wc} words (cap {EXPLANATION_WORD_CAP})")
    if wc < 40:
        warnings.append(f"{mid}: explanation is only {wc} words (likely thin)")
    if "distractor" not in expl.lower() and not any(
        s in expl.lower() for s in ("distractor 1", "distractor 2", "distractor 3", "distractor_")
    ):
        # brief 4.5: explanation must address why each distractor is wrong
        warnings.append(f"{mid}: explanation doesn't reference distractors by label (style only)")

    # Correct-answer-length tell: warn only if correct is dramatically longer than every distractor.
    cl = len(opts.get("correct", ""))
    dlens = [len(opts.get(k, "")) for k in ("distractor_1", "distractor_2", "distractor_3")]
    if all(cl > d * 1.25 for d in dlens) and cl - max(dlens) > 20:
        warnings.append(
            f"{mid}: correct answer is noticeably longer than every distractor (correct={cl} chars, max distractor={max(dlens)})"
        )


def cross_check(mcqs: list, warnings: list):
    # Distinct ids
    ids = [m.get("id") for m in mcqs]
    if len(set(ids)) != len(ids):
        warnings.append(f"duplicate MCQ ids present: {sorted([i for i in ids if ids.count(i) > 1])}")
    # Correct-answer length distribution: at most one MCQ where correct is the longest in its set?
    # We just print a tally so reviewer sees variety.
    longest_is_correct = 0
    for m in mcqs:
        opts = m.get("options", {})
        lengths = {k: len(opts.get(k, "")) for k in REQUIRED_OPTION_KEYS}
        if max(lengths, key=lengths.get) == "correct":
            longest_is_correct += 1
    if longest_is_correct >= len(mcqs) * 0.7 and len(mcqs) >= 5:
        warnings.append(
            f"correct is the longest option in {longest_is_correct}/{len(mcqs)} MCQs — vary the length more"
        )


def main():
    if len(sys.argv) < 2:
        print("usage: validate_mcqs.py <pilot.json>", file=sys.stderr)
        sys.exit(2)
    path = Path(sys.argv[1])
    mcqs = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(mcqs, list):
        print(f"ERROR: {path} should contain a JSON array of MCQs", file=sys.stderr)
        sys.exit(1)
    errors: list = []
    warnings: list = []
    for m in mcqs:
        validate_one(m, errors, warnings)
    cross_check(mcqs, warnings)

    print(f"Validated {len(mcqs)} MCQ(s) in {path}")
    if warnings:
        print("\nWARNINGS:")
        for w in warnings:
            print(f"  - {w}")
    if errors:
        print("\nERRORS:")
        for e in errors:
            print(f"  - {e}")
        sys.exit(1)
    print("OK")


if __name__ == "__main__":
    main()
