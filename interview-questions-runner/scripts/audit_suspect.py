"""Flag suspect distractors that match patterns commonly associated with
fabrication (Stephen's redline category A). Each pattern is a heuristic
that surfaces candidates for manual verification — not all matches are
fabrications, and the script also won't catch all fabrications.

Patterns considered (original set):
  - Deprecation/removal claims with version numbers
  - 'Automatically' / 'implicit' / 'built-in' + specific feature
  - Specific quantitative claims (%, hours, ms) that are unusual
  - Fictional-sounding named features
  - Apparent anti-patterns no candidate would propose

Patterns added 2026-06-02 after the Phase 4 control sample surfaced
fabrications that the original patterns missed:
  - Mechanism-claim: invented internal mechanisms (kernel/buffer/drain
    as cause-effect agents) — template case: docker-010-mcq-2
    distractor_3 ("kernel buffer that the daemon doesn't drain").
  - Invented-constraint: assertions of rules/limits that don't exist
    ("refuses to X if Y", "cannot X without Y first") — template cases:
    git-006-mcq-1 distractor_2, tf-011-mcq-1 distractor_2.
  - Invented-key: YAML/HCL keys that look normal but aren't real,
    matched against an allowlist of common keys per tool — template
    case: cicd-012-mcq-2 distractor_3 ("`skip-matrix:`").

Recall is favoured over precision in the new patterns: over-flagging
generates triage work, under-flagging is what bit us during the
control sample.
"""

import json
import re
from pathlib import Path

QUESTIONS_DIR = Path("cloud-labs/lab-095-interview-drill-mcq/questions")
OUT = Path("interview-questions-runner/phase3-audit/suspect-distractors.json")

SUSPECT_PATTERNS = [
    # ---- Original patterns ----
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

    # ---- Mechanism-claim (added 2026-06-02) ----
    # System-level "container of state" + active verb
    (r"\b(kernel|kernel-level|daemon|daemon-level|driver|cgroup|cfs|syscall)\s+(buffer|queue|drain|cache|pool|table|ring)\b", "mechanism-kernel-internal"),
    # "buffer/queue/cache/pool that does/doesn't X"
    (r"\b(buffer|queue|cache|pool|ring)\s+that\s+(doesn[’']?t|won[’']?t|never|always|silently|gets|periodically)\b", "mechanism-active-buffer"),
    # "silently drops/loses/truncates/fails/swallows"
    (r"\bsilently\s+(drops?|loses?|truncates?|fails?|swallows?|discards?|overwrites?)", "mechanism-silent-failure"),
    # "the underlying X" + system noun
    (r"\bunderlying\s+\w+\s+(buffer|queue|cache|driver|layer|table|store|log)\b", "mechanism-underlying-internal"),
    # "-level" descriptors used to invent layer mechanics
    (r"\b(daemon-level|kernel-level|driver-level|cgroup-level|syscall-level)\b", "mechanism-level-prefix"),
    # "flushed/drained/buffered to/by/at/in (the) kernel/daemon/cgroup/driver/syscall"
    (r"\b(flushed|drained|buffered|swapped)\s+(to|by|at|in)\s+(?:the\s+)?(kernel|daemon|cgroup|driver|syscall|hypervisor)", "mechanism-flush-claim"),
    # Authoritative agent: "the daemon doesn't drain/flush/process X"
    (r"\b(daemon|kernel|driver|controller|scheduler)\s+(doesn[’']?t|won[’']?t|never|fails to)\s+(drains?|flushes?|processes?|reads?|writes?|tracks?)\b", "mechanism-agent-negation"),

    # ---- Invented-constraint (added 2026-06-02) ----
    # "refuses/refusing to X if/until/because/unless/without"
    (r"\b(refuses?|refusing)\s+to\s+\w+(?:\s+\w+){0,3}\s+(?:if|until|because|unless|without)\b", "constraint-refuses"),
    # "cannot/can't/won't X without/until/unless Y"
    (r"\b(cannot|can[’']?t|won[’']?t)\s+\w+(?:\s+\w+){0,3}\s+(?:without|until|unless)\s+", "constraint-cannot-without"),
    # "must (first|always|either) X before/until/without"
    (r"\bmust\s+(first|always|either|otherwise)\s+\w+(?:\s+\w+){0,3}\s+(before|prior\s+to|until|without)\b", "constraint-must-first"),
    # "requires X first/before/prior"
    (r"\brequires?\s+(?:a|the|an)?\s*\w+(?:\s+\w+){0,4}\s+(first|before|prior)\b", "constraint-requires-first"),
    # "until you delete/remove/rerun/run/set/configure/move/rename X"
    (r"\buntil\s+you\s+(delete|remove|rerun|run|set|configure|enable|disable|move|rename|reapply|reimport)\b", "constraint-until-you"),
    # Tool-specific prohibition: "Terraform/Kubernetes/Git/Docker refuses/cannot/won't X"
    (r"\b(Terraform|Kubernetes|kubectl|Git|Docker|Helm|GitHub Actions|the runner|the daemon)\s+(refuses|refuse|cannot|can[’']?t|won[’']?t|will\s+not)\s+\w+", "constraint-tool-prohibits"),

    # ---- Invented-key catch-all (added 2026-06-02; see scan_invented_keys for allowlist-based detection) ----
    # (No regex here — handled by scan_invented_keys below)
]

# Allowlist of real config / manifest keys across the major tools the
# rewrite covers. Recall is favoured: misses are flagged manually rather
# than allowed silently. Add to this list as new real keys are encountered;
# do NOT add suspect keys "to make the flag go away."
REAL_KEYS: set[str] = {
    # ---- GitHub Actions workflow syntax (top-level + common nested) ----
    "name", "on", "jobs", "runs-on", "steps", "uses", "with", "env",
    "permissions", "strategy", "matrix", "include", "exclude", "fail-fast",
    "max-parallel", "if", "continue-on-error", "timeout-minutes", "needs",
    "outputs", "defaults", "concurrency", "cancel-in-progress", "secrets",
    "inputs", "workflow_dispatch", "workflow_call", "workflow_run",
    "pull_request", "pull_request_target", "push", "schedule", "release",
    "issues", "services", "container", "image", "ports", "volumes",
    "credentials", "id", "run", "shell", "working-directory", "type",
    "default", "required", "description", "options", "cron", "branches",
    "branches-ignore", "tags", "tags-ignore", "paths", "paths-ignore",
    "types", "registry", "username", "password", "token", "actions",
    "checks", "contents", "deployments", "discussions", "id-token",
    "issues", "packages", "pages", "pull-requests", "repository-projects",
    "security-events", "statuses",
    # ---- Terraform block keys / arguments ----
    "resource", "data", "provider", "variable", "output", "locals", "module",
    "terraform", "backend", "required_providers", "required_version",
    "source", "version", "count", "for_each", "depends_on", "lifecycle",
    "provisioner", "connection", "dynamic", "sensitive", "validation",
    "nullable", "precondition", "postcondition", "create_before_destroy",
    "prevent_destroy", "ignore_changes", "replace_triggered_by", "alias",
    "configuration_aliases", "experiments", "cloud", "workspaces",
    "hostname", "organization", "config_path", "config_context",
    # ---- Kubernetes manifest fields (common) ----
    "apiVersion", "apiversion", "kind", "metadata", "spec", "status",
    "namespace", "labels", "annotations", "selector", "matchLabels",
    "matchExpressions", "matchlabels", "template", "containers",
    "initContainers", "imagePullPolicy", "imagePullSecrets", "command",
    "args", "resources", "requests", "limits", "cpu", "memory",
    "ephemeral-storage", "envFrom", "valueFrom", "configMapKeyRef",
    "secretKeyRef", "fieldRef", "resourceFieldRef", "volumeMounts",
    "mountPath", "subPath", "configMap", "secret", "emptyDir", "hostPath",
    "persistentVolumeClaim", "claimName", "serviceAccountName",
    "automountServiceAccountToken", "restartPolicy", "nodeSelector",
    "tolerations", "affinity", "nodeAffinity", "podAffinity",
    "podAntiAffinity", "topologyKey", "operator", "values", "key",
    "effect", "tolerationSeconds", "replicas", "rollingUpdate",
    "maxSurge", "maxUnavailable", "revisionHistoryLimit",
    "progressDeadlineSeconds", "livenessProbe", "readinessProbe",
    "startupProbe", "httpGet", "tcpSocket", "exec", "grpc", "path",
    "port", "host", "scheme", "httpHeaders", "initialDelaySeconds",
    "periodSeconds", "timeoutSeconds", "successThreshold",
    "failureThreshold", "terminationGracePeriodSeconds",
    "securityContext", "runAsUser", "runAsGroup", "fsGroup",
    "runAsNonRoot", "privileged", "allowPrivilegeEscalation",
    "readOnlyRootFilesystem", "capabilities", "add", "drop",
    "endpoints", "addresses", "targetPort", "nodePort", "loadBalancerIP",
    "externalIPs", "sessionAffinity", "externalName", "clusterIP",
    "clusterIPs", "ipFamilyPolicy", "ipFamilies", "scaleTargetRef",
    "minReplicas", "maxReplicas", "metrics", "behavior", "scaleUp",
    "scaleDown", "stabilizationWindowSeconds", "policies", "rules",
    "apiGroups", "verbs", "resourceNames", "subjects", "roleRef",
    "ingress", "egress", "from", "to",
    # ---- Dockerfile directives (lowercase forms in case they appear so) ----
    "cmd", "entrypoint", "copy", "arg", "workdir", "expose", "volume",
    "label", "user", "healthcheck", "stopsignal", "onbuild", "maintainer",
    # ---- English-prose colon words to suppress false positives ----
    "note", "example", "examples", "result", "results", "warning",
    "warnings", "caution", "tip", "tips", "see", "also", "details",
    "exception", "context", "scenario", "summary", "conclusion",
    "however", "instead", "rather", "specifically", "namely", "ie",
    "eg", "i", "e", "g", "for", "step", "steps", "case", "phase",
    "tier", "batch", "task", "section", "appendix", "rule",
    "fix", "issue", "bug", "feature", "answer", "question", "stem",
    "correct", "incorrect", "yes", "no", "ok", "wait", "stop",
    "verdict", "decision", "approve", "reject", "hold",
}


def scan_invented_keys(text: str) -> list[str]:
    """Return list of suspect-key labels when text contains YAML/HCL/CLI
    key shapes that are not on the REAL_KEYS allowlist."""
    findings: list[str] = []
    seen: set[str] = set()

    # High-precision pattern: backtick-wrapped `key:` shapes
    for m in re.finditer(r"`([a-zA-Z][a-zA-Z0-9_-]{2,40})\s*:", text):
        key = m.group(1)
        if key not in REAL_KEYS and key.lower() not in REAL_KEYS and key not in seen:
            seen.add(key)
            findings.append(f"key-not-in-allowlist:{key}")

    # Looser pattern: bare YAML-style key: at sentence start or after ", "
    # — only triggers when followed by a value-like token to reduce English-prose noise
    for m in re.finditer(r"(?:^|[\.,]\s+|[\[\{(]\s*)([a-z][a-z0-9_-]{2,40})\s*:\s*(?=\[|\{|`|<|\w)", text):
        key = m.group(1)
        if key not in REAL_KEYS and key not in seen:
            seen.add(key)
            findings.append(f"key-not-in-allowlist-loose:{key}")

    return findings


def scan_distractor(text: str) -> list[str]:
    hits = []
    for pat, label in SUSPECT_PATTERNS:
        if re.search(pat, text):
            hits.append(label)
    hits.extend(scan_invented_keys(text))
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

    # Break down by old vs new pattern groups (added 2026-06-02)
    NEW_GROUPS = {
        "mechanism": {p for p in pat_counts if p.startswith("mechanism-")},
        "constraint": {p for p in pat_counts if p.startswith("constraint-")},
        "key": {p for p in pat_counts if p.startswith("key-not-in-allowlist")},
    }
    print()
    print("--- New pattern groups (added 2026-06-02) ---")
    for grp, labels in NEW_GROUPS.items():
        rows = [r for r in out_rows if any(p in labels for p in r["patterns"])]
        ids = {r["id"] for r in rows}
        print(f"  {grp:12s} distinct MCQs: {len(ids):3d}  entries: {len(rows):3d}  labels: {sorted(labels)}")


if __name__ == "__main__":
    main()
