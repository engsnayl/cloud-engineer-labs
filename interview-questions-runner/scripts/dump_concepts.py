"""Dump per-source concepts to a single readable text file."""
import json
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
qs = json.loads(Path("interview-questions-runner/phase1/sources.json").read_text(encoding="utf-8"))

for d in ["aws", "kubernetes", "cicd", "terraform", "docker", "linux", "git"]:
    print(f"\n===== {d.upper()} =====")
    for q in qs:
        if q["domain_dir"] != d:
            continue
        print(f"\n{q['id']} | {q['priority']} | {q['difficulty']}")
        print(f"  Q: {q['stem']}")
        for c in q["concepts"]:
            print(f"  - {c}")
