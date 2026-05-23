#!/usr/bin/env bash
# quickfire.sh - rapid-fire git question session
# Called from gitdrill.sh - not meant to be run directly.
#
# Usage (via gitdrill wrapper):
#   gitdrill quickfire [N]     - run N questions (default 20)
#   gitdrill quickfire all     - run every question once, shuffled
#   gitdrill progress          - show session history and weak spots

set -uo pipefail

GITDRILL_ROOT="${GITDRILL_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
QUESTIONS_DIR="${GITDRILL_ROOT}/quickfire/questions"
PROGRESS_FILE="${HOME}/.gitdrill-progress.json"

# Colors
if [[ -t 1 ]]; then
    C_RED=$'\033[0;31m'; C_GREEN=$'\033[0;32m'; C_YELLOW=$'\033[0;33m'
    C_BLUE=$'\033[0;34m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
else
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_BOLD=''; C_DIM=''; C_RESET=''
fi

_qf_die()  { printf '%sERROR:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
_qf_info() { printf '%s%s%s\n' "$C_BLUE" "$*" "$C_RESET"; }

# Parse one section from a question file.
# Usage: _qf_section <file> <SECTION_NAME>
_qf_section() {
    local file="$1" name="$2"
    awk -v section="---${name}---" '
        $0 == "---SCENARIO---" || $0 == "---ACCEPT---" || $0 == "---CANONICAL---" || $0 == "---EXPLAIN---" {
            if ($0 == section) { in_section = 1; next }
            else { in_section = 0; next }
        }
        in_section { print }
    ' "$file"
}

# Get a metadata field from a question file's header comments.
# Usage: _qf_meta <file> <key>
_qf_meta() {
    local file="$1" key="$2"
    grep -m 1 "^# ${key}:" "$file" | sed "s/^# ${key}: //"
}

# Normalise a command string for matching: collapse whitespace, trim.
_qf_normalise() {
    # shellcheck disable=SC2001
    sed -e 's/[[:space:]]\+/ /g' -e 's/^ //' -e 's/ $//'
}

# Check if a user's answer matches any line in the ACCEPT section.
# Returns 0 on match, 1 on no-match.
# Usage: _qf_check <question_file> <user_input>
_qf_check() {
    local file="$1" user_raw="$2"
    local user
    user=$(printf '%s' "$user_raw" | _qf_normalise)
    [[ -z "$user" ]] && return 1
    local accepted
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        accepted=$(printf '%s' "$line" | _qf_normalise)
        if [[ "$user" == "$accepted" ]]; then
            return 0
        fi
    done < <(_qf_section "$file" "ACCEPT")
    return 1
}

# Append a result to the progress JSON file. Creates it if missing.
# Usage: _qf_log_result <question_id> <correct: 0|1> <duration_seconds>
_qf_log_result() {
    local qid="$1" correct="$2" duration="$3"
    local ts
    ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    python3 - "$PROGRESS_FILE" "$qid" "$correct" "$duration" "$ts" <<'PYEOF'
import json, os, sys
path, qid, correct, duration, ts = sys.argv[1:6]
correct = bool(int(correct))
duration = int(duration)

if os.path.exists(path):
    with open(path) as f:
        try:
            data = json.load(f)
        except Exception:
            data = {}
else:
    data = {}

data.setdefault("quickfire", {})
q = data["quickfire"].setdefault(qid, {
    "attempts": 0,
    "correct": 0,
    "wrong": 0,
    "last_attempted": None,
    "last_correct": None,
})
q["attempts"] += 1
if correct:
    q["correct"] += 1
    q["last_correct"] = ts
else:
    q["wrong"] += 1
q["last_attempted"] = ts

with open(path, "w") as f:
    json.dump(data, f, indent=2)
PYEOF
}

# Get a list of all question files, shuffled.
_qf_list_shuffled() {
    find "$QUESTIONS_DIR" -maxdepth 1 -name "q*.md" -type f 2>/dev/null | shuf
}

# Run a quickfire session.
# Usage: quickfire_session <count>
quickfire_session() {
    local count="${1:-20}"
    if [[ "$count" == "all" ]]; then
        count=$(find "$QUESTIONS_DIR" -maxdepth 1 -name "q*.md" -type f | wc -l)
    fi
    [[ "$count" =~ ^[0-9]+$ ]] || _qf_die "Count must be a number or 'all'"
    local total_available
    total_available=$(find "$QUESTIONS_DIR" -maxdepth 1 -name "q*.md" -type f | wc -l)
    [[ "$total_available" -gt 0 ]] || _qf_die "No questions found in $QUESTIONS_DIR"
    [[ "$count" -le "$total_available" ]] || count="$total_available"

    # Pick the question set
    local -a questions
    mapfile -t questions < <(_qf_list_shuffled | head -n "$count")

    printf '%s%s%s\n' "$C_BOLD" "════════════════════════════════════════════════════════════" "$C_RESET"
    printf '%s  Quickfire session: %d questions%s\n' "$C_BOLD" "$count" "$C_RESET"
    printf '%s  Type your answer and press Enter. Type :skip to skip, :quit to stop.%s\n' "$C_DIM" "$C_RESET"
    printf '%s%s%s\n\n' "$C_BOLD" "════════════════════════════════════════════════════════════" "$C_RESET"

    local correct=0 wrong=0 skipped=0
    local wrong_ids=()
    local skipped_ids=()
    local session_start
    session_start=$(date +%s)

    local i=0
    for q in "${questions[@]}"; do
        i=$((i + 1))
        local qid
        qid=$(_qf_meta "$q" "id")
        local topic
        topic=$(_qf_meta "$q" "topic")
        local scenario
        scenario=$(_qf_section "$q" "SCENARIO" | sed '/^$/N;/^\n$/D')   # collapse blank-blank

        printf '%s[%d/%d]%s %s%s%s\n' "$C_BOLD" "$i" "$count" "$C_RESET" "$C_DIM" "($topic)" "$C_RESET"
        printf '%s\n' "$scenario"
        printf '%s>%s ' "$C_BLUE" "$C_RESET"

        local q_start q_end duration
        q_start=$(date +%s)
        local user_input=""
        IFS= read -r user_input || { printf '\n'; break; }
        q_end=$(date +%s)
        duration=$((q_end - q_start))

        # Special commands
        if [[ "$user_input" == ":quit" ]]; then
            printf '%sSession ended early.%s\n\n' "$C_YELLOW" "$C_RESET"
            break
        fi
        if [[ "$user_input" == ":skip" ]]; then
            skipped=$((skipped + 1))
            skipped_ids+=("$qid")
            local canon
            canon=$(_qf_section "$q" "CANONICAL" | head -n 1)
            printf '%s↷ skipped.%s Canonical: %s%s%s\n\n' \
                "$C_YELLOW" "$C_RESET" "$C_BOLD" "$canon" "$C_RESET"
            continue
        fi

        if _qf_check "$q" "$user_input"; then
            correct=$((correct + 1))
            printf '%s✓ correct%s (%ds)\n\n' "$C_GREEN" "$C_RESET" "$duration"
            _qf_log_result "$qid" 1 "$duration"
        else
            wrong=$((wrong + 1))
            wrong_ids+=("$qid")
            local canon explain
            canon=$(_qf_section "$q" "CANONICAL" | head -n 1)
            explain=$(_qf_section "$q" "EXPLAIN")
            printf '%s✗ wrong.%s Canonical: %s%s%s\n' \
                "$C_RED" "$C_RESET" "$C_BOLD" "$canon" "$C_RESET"
            [[ -n "$explain" ]] && printf '%s%s%s\n' "$C_DIM" "$explain" "$C_RESET"
            printf '\n'
            _qf_log_result "$qid" 0 "$duration"
        fi
    done

    local session_end total_time
    session_end=$(date +%s)
    total_time=$((session_end - session_start))
    local attempted=$((correct + wrong))

    printf '%s%s%s\n' "$C_BOLD" "════════════════════════════════════════════════════════════" "$C_RESET"
    printf '%sSession summary%s\n' "$C_BOLD" "$C_RESET"
    printf '  Attempted: %d / %d\n' "$attempted" "$count"
    printf '  %sCorrect:%s   %d\n' "$C_GREEN" "$C_RESET" "$correct"
    printf '  %sWrong:%s     %d\n' "$C_RED" "$C_RESET" "$wrong"
    printf '  %sSkipped:%s   %d\n' "$C_YELLOW" "$C_RESET" "$skipped"
    if [[ "$attempted" -gt 0 ]]; then
        local pct=$((correct * 100 / attempted))
        printf '  Accuracy:  %d%%\n' "$pct"
    fi
    printf '  Time:      %dm %ds\n' "$((total_time / 60))" "$((total_time % 60))"
    if (( ${#wrong_ids[@]} > 0 )); then
        printf '\n%sQuestions to revisit:%s %s\n' "$C_RED" "$C_RESET" "${wrong_ids[*]}"
    fi
    if (( ${#skipped_ids[@]} > 0 )); then
        printf '%sSkipped:%s %s\n' "$C_YELLOW" "$C_RESET" "${skipped_ids[*]}"
    fi
    printf '%s%s%s\n' "$C_BOLD" "════════════════════════════════════════════════════════════" "$C_RESET"
}

# Show progress across all questions ever attempted.
quickfire_progress() {
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        printf 'No quickfire history yet. Run %sgitdrill quickfire%s to start.\n' "$C_BOLD" "$C_RESET"
        return 0
    fi
    python3 - "$PROGRESS_FILE" "$QUESTIONS_DIR" <<'PYEOF'
import json, os, sys, glob

progress_path, qdir = sys.argv[1], sys.argv[2]

with open(progress_path) as f:
    data = json.load(f)

qf = data.get("quickfire", {})
if not qf:
    print("No quickfire history yet.")
    sys.exit(0)

# Build topic lookup from question files
topics = {}
for f in glob.glob(os.path.join(qdir, "q*.md")):
    qid = topic = ""
    with open(f) as fh:
        for line in fh:
            if line.startswith("# id:"):     qid   = line.split(":",1)[1].strip()
            if line.startswith("# topic:"):  topic = line.split(":",1)[1].strip()
            if line.startswith("---"):       break
    if qid:
        topics[qid] = topic

total_attempts = sum(q["attempts"] for q in qf.values())
total_correct  = sum(q["correct"]  for q in qf.values())
total_wrong    = sum(q["wrong"]    for q in qf.values())
unique_seen    = len(qf)
total_questions = len(topics) or unique_seen

print()
print(f"  Quickfire progress")
print(f"  ─────────────────────────────────────────────")
print(f"  Total attempts:   {total_attempts}")
print(f"  Correct:          {total_correct}")
print(f"  Wrong:            {total_wrong}")
if total_attempts:
    print(f"  Overall accuracy: {total_correct * 100 // total_attempts}%")
print(f"  Unique questions seen: {unique_seen} / {total_questions}")
print()

# Weak spots: any question with more wrong than correct attempts
weak = [(qid, q) for qid, q in qf.items() if q["wrong"] > q["correct"]]
weak.sort(key=lambda x: x[1]["wrong"] - x[1]["correct"], reverse=True)
if weak:
    print(f"  Weak spots (more wrong than right):")
    print(f"  {'ID':<8} {'W':>3} {'C':>3}  Topic")
    print(f"  {'─'*8} {'─'*3} {'─'*3}  {'─'*40}")
    for qid, q in weak[:15]:
        topic = topics.get(qid, "?")[:40]
        print(f"  {qid:<8} {q['wrong']:>3} {q['correct']:>3}  {topic}")
    print()

# Never seen
unseen = [qid for qid in topics if qid not in qf]
if unseen:
    print(f"  Not yet attempted: {len(unseen)} questions")
    print()
PYEOF
}

# Dispatch from gitdrill wrapper
case "${1:-}" in
    session)  shift; quickfire_session "$@" ;;
    progress) shift; quickfire_progress "$@" ;;
    *)        _qf_die "Internal: unknown quickfire subcommand: ${1:-}" ;;
esac
