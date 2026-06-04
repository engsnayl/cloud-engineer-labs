#!/usr/bin/env bash
# validate.sh — structural validation for the Interview Drill lab (brief 8.2).
# This is NOT a "does it grade correctly" test (that's the manual smoke test);
# it confirms the banks are well-formed and the runner scripts are in place.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QDIR="$DIR/questions"
fail=0
pass() { printf '  [PASS] %s\n' "$1"; }
fault() { printf '  [FAIL] %s\n' "$1"; fail=1; }

echo "Interview Drill — structural validation"
echo "──────────────────────────────────────"

# 1) jq present
if command -v jq >/dev/null 2>&1; then
  pass "jq is installed"
else
  fault "jq is not installed (required) — install with: sudo apt-get install -y jq"
  echo; echo "Cannot continue without jq."; exit 1
fi

for n in 1 2 3; do
  f="$QDIR/interview-$n.json"

  # 2) parses + count in range
  if [[ ! -f "$f" ]]; then fault "interview-$n.json is missing"; continue; fi
  if ! jq empty "$f" >/dev/null 2>&1; then fault "interview-$n.json is not valid JSON"; continue; fi
  count=$(jq 'length' "$f")
  if (( count >= 60 && count <= 80 )); then
    pass "interview-$n.json parses — $count MCQs (within 60-80)"
  else
    fault "interview-$n.json has $count MCQs (expected 60-80)"
  fi

  # 3) required fields present on every MCQ
  bad_fields=$(jq -r '
    [ .[]
      | select(
          (has("id") and has("source_id") and has("domain") and has("subdomain")
           and has("priority") and has("difficulty") and has("question")
           and has("options") and has("explanation")) | not)
      | .id // "<no id>" ] | length' "$f")
  if (( bad_fields == 0 )); then pass "interview-$n.json — all MCQs have required fields"
  else fault "interview-$n.json — $bad_fields MCQ(s) missing required fields"; fi

  # 4) exactly 4 options with the expected keys
  bad_opts=$(jq -r '
    [ .[]
      | select(
          (.options | type == "object"
            and has("correct") and has("distractor_1")
            and has("distractor_2") and has("distractor_3")
            and (keys | length) == 4) | not)
      | .id ] | length' "$f")
  if (( bad_opts == 0 )); then pass "interview-$n.json — every MCQ has exactly 4 named options"
  else fault "interview-$n.json — $bad_opts MCQ(s) without exactly 4 options"; fi

  # 5 + 6) all four option texts distinct (no duplicate distractors; correct not reused as a distractor)
  dup=$(jq -r '
    [ .[]
      | select(.options
          | [.correct, .distractor_1, .distractor_2, .distractor_3]
          | (unique | length) != 4)
      | .id ] | length' "$f")
  if (( dup == 0 )); then pass "interview-$n.json — no duplicate option texts within any MCQ"
  else fault "interview-$n.json — $dup MCQ(s) with a duplicated option (distractor clash or correct reused)"; fi
done

# 7) runner.sh executable
if [[ -x "$DIR/runner.sh" ]]; then pass "runner.sh is executable"
else fault "runner.sh is not executable (chmod +x runner.sh)"; fi

# 8) lib scripts present
for l in timer shuffle scoring display; do
  if [[ -f "$DIR/lib/$l.sh" ]]; then pass "lib/$l.sh exists"
  else fault "lib/$l.sh is missing"; fi
done

echo "──────────────────────────────────────"
if (( fail == 0 )); then
  echo "All structural checks passed."
  exit 0
else
  echo "One or more checks failed (see [FAIL] above)."
  exit 1
fi
