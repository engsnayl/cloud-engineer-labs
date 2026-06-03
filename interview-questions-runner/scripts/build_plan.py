"""Emit the Phase 1 plan markdown by combining allocation + angles."""

import json
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from angles import ANGLES  # noqa: E402

ALLOC = Path("interview-questions-runner/phase1/allocation.json")
OUT = Path("interview-questions-runner/phase1/PHASE1-PLAN.md")

DOMAIN_LABEL = {
    "aws": "AWS",
    "kubernetes": "Kubernetes",
    "cicd": "CI/CD",
    "terraform": "Terraform",
    "docker": "Docker",
    "linux": "Linux",
    "git": "Git",
}

DOMAIN_ORDER = ["aws", "kubernetes", "cicd", "terraform", "docker", "linux", "git"]


def main():
    data = json.loads(ALLOC.read_text(encoding="utf-8"))
    rows = data["allocation"]
    summary = data["summary"]

    out = []
    out.append("# Phase 1 Plan — Interview Drill Runner (MCQ)\n")
    out.append(
        "Source-by-source allocation and concept-angle outlines for the 3 MCQ banks.\n"
        "**No MCQs authored yet** — this is the sign-off gate before Phase 2.\n"
    )
    out.append("## Inputs\n")
    out.append(
        "- **Source file:** `Interview Prep App/Interview-Prep-Combined.md`\n"
        "  - Note: the brief's raw URL `https://raw.githubusercontent.com/engsnayl/interview-prep-app/main/Interview-Prep-Combined.md` returns 404 (private or moved), so this plan uses the local copy already present in the labs repo. Counts match the brief exactly.\n"
        "- **Sources parsed:** 110 total → 104 after excluding 6 behavioural items (`beh-001`–`beh-006`)\n"
        "- **Target MCQs:** 2 per source × 104 sources = **208 MCQs across 3 banks**\n"
    )

    out.append("## Domain totals (matches Section 2 of the brief)\n")
    out.append("| Domain | Source questions | MCQs (×2) |")
    out.append("|---|---|---|")
    counter = Counter(r["domain"] for r in rows)
    total_sources = 0
    total_mcqs = 0
    for d in DOMAIN_ORDER:
        n = counter[d]
        total_sources += n
        total_mcqs += n * 2
        out.append(f"| {DOMAIN_LABEL[d]} | {n} | {n*2} |")
    out.append(f"| **Total** | **{total_sources}** | **{total_mcqs}** |")
    out.append("")

    out.append("## Bank composition\n")
    out.append("Bank totals: " + ", ".join(f"Bank {b} = **{summary['bank_totals'][str(b)]}**" for b in (1, 2, 3)) + ".\n")
    out.append("| Domain | Bank 1 | Bank 2 | Bank 3 | Brief target |")
    out.append("|---|---|---|---|---|")
    brief_targets = {
        "aws": "18-19",
        "kubernetes": "14-15",
        "cicd": "12",
        "terraform": "8-9",
        "docker": "6-7",
        "linux": "4-5",
        "git": "4",
    }
    for d in DOMAIN_ORDER:
        bt = summary["domain_bank_totals"][d]
        out.append(
            f"| {DOMAIN_LABEL[d]} | {bt['1']} | {bt['2']} | {bt['3']} | {brief_targets[d]} |"
        )
    out.append(
        f"| **Total** | **{summary['bank_totals']['1']}** "
        f"| **{summary['bank_totals']['2']}** "
        f"| **{summary['bank_totals']['3']}** | ~69 |"
    )
    out.append("")

    out.append("### Priority spread per bank\n")
    out.append("Every bank contains a mix of critical / high / medium so each Interview feels representative. Low (2 sources total) is in banks 2 and 3.\n")
    out.append("| Bank | critical | high | medium | low |")
    out.append("|---|---|---|---|---|")
    for b in ("1", "2", "3"):
        p = summary["priority_bank_totals"][b]
        out.append(
            f"| {b} | {p.get('critical', 0)} | {p.get('high', 0)} | {p.get('medium', 0)} | {p.get('low', 0)} |"
        )
    out.append("")

    out.append("## Allocation strategy\n")
    out.append(
        "For each source, the **2 MCQs go into different banks** (per brief Section 3.2). "
        "That pair is one of `(1,2)`, `(1,3)`, or `(2,3)`. Domain capacities and pair-type "
        "quotas are solved algebraically so the per-bank-per-domain totals match the table above.\n"
    )
    out.append("**Pair-type quotas per domain** (each entry = number of sources assigned that pair):\n")
    out.append("| Domain | (1,2) | (1,3) | (2,3) |")
    out.append("|---|---|---|---|")
    for d in DOMAIN_ORDER:
        q = summary["domain_pair_quotas"][d]
        out.append(f"| {DOMAIN_LABEL[d]} | {q['(1,2)']} | {q['(1,3)']} | {q['(2,3)']} |")
    out.append("")
    out.append(
        "Within each domain, sources are sorted by priority (critical → high → medium → low) and "
        "assigned round-robin across pair types so every bank gets a healthy slice of the "
        "high-priority material.\n"
    )

    out.append("## Per-source allocation and concept angles\n")
    out.append(
        "Each row lists the source, its priority, which two banks its MCQs go to (MCQ 1 → lower-numbered bank, "
        "MCQ 2 → higher), and one-sentence outlines for each MCQ. Outlines are deliberately distinct facets "
        "so the two MCQs don't duplicate each other.\n"
    )

    for d in DOMAIN_ORDER:
        ds = [r for r in rows if r["domain"] == d]
        out.append(f"### {DOMAIN_LABEL[d]} ({len(ds)} sources → {len(ds)*2} MCQs)\n")
        out.append("| Source | Pr | Banks | MCQ 1 angle | MCQ 2 angle |")
        out.append("|---|---|---|---|---|")
        # Sort by source id for stable reading order.
        for r in sorted(ds, key=lambda x: x["id"]):
            a1, a2 = ANGLES[r["id"]]
            banks = f"{r['mcq_1_bank']}+{r['mcq_2_bank']}"
            pr = {"critical": "C", "high": "H", "medium": "M", "low": "L"}[r["priority"]]
            out.append(
                f"| `{r['id']}` | {pr} | {banks} | _(B{r['mcq_1_bank']})_ {a1} | _(B{r['mcq_2_bank']})_ {a2} |"
            )
        out.append("")

    out.append("## What I need from Stephen before Phase 2\n")
    out.append("Sign-off (or redlines) on:\n")
    out.append("1. **Domain/bank split** — does the 70/69/69 split with the priority spread above look balanced enough?\n")
    out.append("2. **Pair allocation** — any source whose two MCQs should NOT go in the bank pair shown?\n")
    out.append("3. **Concept angles** — any source where the two angles overlap too much, or miss the most testable concept?\n")
    out.append("4. **Lab number / location** — brief says `cloud-labs/project-XXX-interview-drill/` but the repo convention is `lab-NNN-kebab-name`. Last lab is 092 with a gap at 088-089. Confirm whether to use `lab-093` (next sequence head) or fill `lab-088`.\n")
    out.append("5. **Source URL** — `raw.githubusercontent.com/engsnayl/interview-prep-app/main/Interview-Prep-Combined.md` returns 404. Should I keep using the local copy at `Interview Prep App/Interview-Prep-Combined.md`, or is the repo URL meant to be public?\n")

    OUT.write_text("\n".join(out), encoding="utf-8")
    print(f"Wrote {OUT} ({len(out)} lines)")


if __name__ == "__main__":
    main()
