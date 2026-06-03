"""Build the final flagged-mcqs.json by combining:
 - Programmatic flags from audit.py (C: NOT/never; D: definition-style stem)
 - Manually-confirmed A flags (fabricated distractors)
 - Manually-confirmed B flags (match-style with 2+ scrambled distractors)

Output schema: one row per MCQ that needs review, with categories and
notes pointing at the specific issue.
"""

import json
from pathlib import Path

QUESTIONS_DIR = Path("cloud-labs/lab-095-interview-drill-mcq/questions")
DRAFT = Path("interview-questions-runner/phase3-audit/draft-audit.json")
OUT = Path("interview-questions-runner/phase3-audit/flagged-mcqs.json")

# Manually confirmed A flags (fabricated distractors that fail the
# "real misconception" test). Each entry names the specific distractor.
A_FABRICATED = {
    "tf-005-mcq-1": {
        "distractor": "distractor_3",
        "note": "Fabricated: Terraform did not deprecate or remove workspaces — they still exist in 1.x. Stephen-flagged example.",
    },
    "k8s-001-mcq-2": {
        "distractor": "distractor_3",
        "note": "Fabricated: Deployments and ReplicaSets share the same container runtime — no runtime-restriction distinction exists. Stephen-flagged example.",
    },
    "k8s-051-mcq-2": {
        "distractor": "distractor_3",
        "note": "Wrong by ~50x: real Istio sidecar overhead is 1-10ms per hop, not 450ms. Stephen-flagged example.",
    },
    "docker-002-mcq-2": {
        "distractor": "distractor_3",
        "note": "Anti-pattern no candidate would propose: 'embed SSL/TLS private key in image'. Stephen-flagged example.",
    },
    "docker-009-mcq-2": {
        "distractor": "distractor_1",
        "note": "Fabricated: ECR has no immutable-tag billing tier. Stephen-flagged example.",
    },
    "aws-035-mcq-1": {
        "distractor": "distractor_1",
        "note": "Fabricated: HTTP API was not deprecated in 2023 — it remains AWS-recommended for new builds.",
    },
    "k8s-041-mcq-2": {
        "distractor": "distractor_2",
        "note": "Fabricated: IRSA is not deprecated nor scheduled for removal in EKS 1.30. Both IRSA and Pod Identity coexist.",
    },
    "k8s-011-mcq-1": {
        "distractor": "distractor_3",
        "note": "Fabricated: there is no 'EKS built-in Ingress provider' and ALB provisioning is ~1-3 minutes, not 30-60.",
    },
    "cicd-013-mcq-2": {
        "distractor": "distractor_1",
        "note": "Fabricated: GitHub Actions does not automatically synchronise BuildKit local caches across runners.",
    },
    "git-006-mcq-2": {
        "distractor": "distractor_1",
        "note": "Fabricated: GitHub does not automatically purge keys from historical commits within 24 hours.",
    },
    "cicd-020-mcq-2": {
        "distractor": "distractor_3",
        "note": "Fabricated: GitHub OIDC JWTs do not include an implicit MFA claim derived from the user's session.",
    },
    "cicd-002-mcq-2": {
        "distractor": "distractor_1",
        "note": "Over-stated: CI speed does not scale linearly with runner size; bigger runners help marginally. The 'always' was caught earlier, but the underlying premise is still false enough to be a fabrication.",
    },
    "aws-022-mcq-1": {
        "distractor": "distractor_1",
        "note": "Fabricated: Fargate has no 15-minute task timeout. The fabricated parallel to Lambda's limit is plausible-sounding but wrong.",
    },
    "aws-031-mcq-2": {
        "distractor": "distractor_3",
        "note": "Fabricated: Restart does not trigger a 'CloudWatch billing event because of the metric stream interruption'.",
    },
    "k8s-021-mcq-2": {
        "distractor": "distractor_2",
        "note": "Fabricated: there is no `scheduler.alpha.kubernetes.io/balanced=true` annotation.",
    },
    "k8s-031-mcq-2": {
        "distractor": "distractor_1",
        "note": "Fabricated: there is no cluster-wide `ExternalSecretsViewer` ClusterRole shipped with ESO.",
    },
    "cicd-031-mcq-1": {
        "distractor": "distractor_2",
        "note": "Over-stated: PostgreSQL/MySQL column rename is not universally a metadata-only operation; this glosses over real locking behaviour.",
    },
    "aws-016-mcq-2": {
        "distractor": "distractor_3",
        "note": "Fabricated: failover routing has no cross-region requirement; same-region secondaries are not 'silently disabled'.",
    },
    "tf-009-mcq-1": {
        "distractor": "distractor_3",
        "note": "Over-stated: 'a single terraform apply weekly' isn't a real or accepted pattern — the distractor invents a process that no team would advocate.",
    },
}

# Match-style MCQs with 2+ full-scramble distractors that collapse to
# elimination-by-format. Stephen flagged cicd-010 and k8s-023.
B_SCRAMBLES = {
    "cicd-010-mcq-1": "All three distractors are pure hierarchy inversions — collapses to 'find the unscrambled answer'. Stephen-flagged example.",
    "k8s-023-mcq-1": "D1 and D3 are scrambles of the autoscaler mapping; only D2 is a different shape. Stephen-flagged example.",
    "cicd-040-mcq-1": "D1 and D2 are full scrambles of the SAST/DAST/SCA/container assignment; only D3 is a different shape.",
    "tf-004-mcq-1": "D1 reverses the precedence order entirely; D3 scrambles it. Only D2 is a different concept ('all sources merged').",
}


def build():
    draft = {r["id"]: r for r in json.loads(DRAFT.read_text(encoding="utf-8"))}

    out = []
    seen = set()
    # Iterate in a stable order across all MCQs
    for mid in sorted(draft.keys()):
        r = draft[mid]
        flags = list(r["flags"])  # C and D from heuristics
        notes = list(r["notes"])

        if mid in A_FABRICATED:
            flags.append("A_fabricated")
            entry = A_FABRICATED[mid]
            notes.append(f"A: {entry['distractor']} — {entry['note']}")

        if mid in B_SCRAMBLES:
            flags.append("B_scrambles")
            notes.append(f"B: {B_SCRAMBLES[mid]}")

        if not flags:
            continue
        out.append(
            {
                "id": mid,
                "domain": r["domain"],
                "bank": r["bank"],
                "stem_type": r["stem_type"],
                "flags": flags,
                "notes": notes,
                "stem_preview": r["question"],
            }
        )
        seen.add(mid)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(out, indent=2), encoding="utf-8")

    # Summary
    from collections import Counter
    cat_counts = Counter()
    for r in out:
        for f in r["flags"]:
            cat_counts[f] += 1
    print(f"Total MCQs flagged for any reason: {len(out)} of 208 ({100*len(out)/208:.0f}%)")
    print(f"By category:")
    for cat, n in sorted(cat_counts.items()):
        print(f"  {cat}: {n}")
    # Breakdown of how many are *only* D vs multiple categories
    only_d = sum(1 for r in out if set(r["flags"]) == {"D_definition"} or set(r["flags"]) == {"D_match_style"})
    multiple_cats = sum(1 for r in out if len({f.split("_")[0] for f in r["flags"]}) > 1)
    has_A_or_B_or_C = sum(1 for r in out if any(f.startswith(("A_", "B_", "C_")) for f in r["flags"]))
    print(f"\nFlagged with A, B, or C (structural issues): {has_A_or_B_or_C}")
    print(f"Flagged ONLY with D (recall-style stem): {only_d}")
    print(f"Flagged with multiple categories: {multiple_cats}")


if __name__ == "__main__":
    build()
