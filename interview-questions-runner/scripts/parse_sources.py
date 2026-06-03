"""Phase 1 parser: extract per-source metadata from Interview-Prep-Combined.md."""

import json
import re
import sys
from pathlib import Path

SRC = Path("Interview Prep App/Interview-Prep-Combined.md")
OUT = Path("interview-questions-runner/phase1/sources.json")

FILE_RE = re.compile(r"^# === FILE: ([a-z]+)/([a-z0-9\-]+)\.md ===\s*$")
FRONT_OPEN = "---"
H1_RE = re.compile(r"^# (?!===)(.+?)\s*$")
CONCEPTS_RE = re.compile(r"^## Concepts being tested\s*$")


def parse():
    text = SRC.read_text(encoding="utf-8")
    lines = text.splitlines()
    questions = []
    i = 0
    n = len(lines)
    while i < n:
        m = FILE_RE.match(lines[i])
        if not m:
            i += 1
            continue
        domain_dir, slug = m.group(1), m.group(2)
        # Find frontmatter
        j = i + 1
        while j < n and lines[j].strip() == "":
            j += 1
        if j >= n or lines[j].strip() != FRONT_OPEN:
            i = j
            continue
        fm_start = j + 1
        fm_end = fm_start
        while fm_end < n and lines[fm_end].strip() != FRONT_OPEN:
            fm_end += 1
        fm = parse_frontmatter(lines[fm_start:fm_end])
        # H1 question stem
        k = fm_end + 1
        while k < n and lines[k].strip() == "":
            k += 1
        stem = ""
        if k < n:
            mm = H1_RE.match(lines[k])
            if mm:
                stem = mm.group(1).strip()
        # Concepts being tested (bullets) — first set after H1
        concepts = []
        c = k + 1 if k < n else n
        while c < n and not FILE_RE.match(lines[c]):
            if CONCEPTS_RE.match(lines[c]):
                c += 1
                # skip blank
                while c < n and lines[c].strip() == "":
                    c += 1
                while c < n and lines[c].strip().startswith("- "):
                    concepts.append(lines[c].strip()[2:].strip())
                    c += 1
                break
            c += 1
        questions.append(
            {
                "id": fm.get("id") or slug,
                "domain_dir": domain_dir,
                "domain_label": fm.get("domain"),
                "subdomain": fm.get("subdomain"),
                "priority": fm.get("priority"),
                "difficulty": fm.get("difficulty"),
                "stem": stem,
                "concepts": concepts,
            }
        )
        i = c if c > i else i + 1
    return questions


def parse_frontmatter(block):
    out = {}
    for line in block:
        if ":" not in line:
            continue
        if line.startswith("  -") or line.startswith("- "):
            continue
        key, _, val = line.partition(":")
        key = key.strip()
        val = val.strip()
        if val.startswith("[") and val.endswith("]"):
            val = [v.strip() for v in val[1:-1].split(",") if v.strip()]
        elif val == "":
            val = None
        out[key] = val
    return out


def main():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    qs = parse()
    OUT.write_text(json.dumps(qs, indent=2), encoding="utf-8")
    # Summary to stderr
    from collections import Counter

    by_domain = Counter(q["domain_dir"] for q in qs)
    by_priority = Counter(q["priority"] for q in qs)
    print(f"Total parsed: {len(qs)}", file=sys.stderr)
    print(f"By domain: {dict(sorted(by_domain.items()))}", file=sys.stderr)
    print(f"By priority: {dict(sorted(by_priority.items(), key=lambda x: str(x[0])))}", file=sys.stderr)
    excl = [q for q in qs if q["domain_dir"] == "behavioural"]
    print(f"Behavioural (will be excluded): {len(excl)} ({[q['id'] for q in excl]})", file=sys.stderr)


if __name__ == "__main__":
    main()
