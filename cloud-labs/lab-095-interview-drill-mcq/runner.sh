#!/usr/bin/env bash
# runner.sh — Interview Drill (MCQ) main loop.
# Entry points: ./runner.sh  |  `lab start 095`  |  the `interview` shortcut.
# Resolves its own directory, so it works regardless of the caller's cwd.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/display.sh
source "$SCRIPT_DIR/lib/display.sh"
# shellcheck source=lib/timer.sh
source "$SCRIPT_DIR/lib/timer.sh"
# shellcheck source=lib/shuffle.sh
source "$SCRIPT_DIR/lib/shuffle.sh"
# shellcheck source=lib/scoring.sh
source "$SCRIPT_DIR/lib/scoring.sh"

QDIR="$SCRIPT_DIR/questions"
SESSION_LABEL=""
SESSION_STARTED=0

cleanup() { tput cnorm 2>/dev/null || true; }
trap cleanup EXIT

# Ctrl+C: show partial results if a session is in progress, then exit cleanly.
on_interrupt() {
  trap - INT
  echo
  if [[ "$SESSION_STARTED" -eq 1 ]]; then
    scoring_results "$SESSION_LABEL" "$(timer_elapsed)"
  fi
  exit 0
}
trap on_interrupt INT

require_deps() {
  local missing=()
  command -v jq   >/dev/null 2>&1 || missing+=("jq")
  command -v shuf >/dev/null 2>&1 || missing+=("shuf (coreutils)")
  if (( ${#missing[@]} )); then
    printf '%sMissing required tools: %s%s\n' "$C_RED" "${missing[*]}" "$C_RESET" >&2
    echo "On the Pi: sudo apt-get install -y jq coreutils" >&2
    exit 1
  fi
}

# load_bank <file>  -> echoes question count; non-zero + message on any problem.
load_bank() {
  local f="$1"
  if [[ ! -f "$f" ]]; then
    printf '%sBank file not found: %s%s\n' "$C_RED" "$f" "$C_RESET" >&2; return 1
  fi
  if ! jq empty "$f" >/dev/null 2>&1; then
    printf '%sBank JSON is malformed: %s%s\n' "$C_RED" "$f" "$C_RESET" >&2; return 1
  fi
  local n; n=$(jq 'length' "$f" 2>/dev/null)
  if [[ -z "$n" || "$n" -lt 1 ]]; then
    printf '%sNo questions in: %s%s\n' "$C_RED" "$f" "$C_RESET" >&2; return 1
  fi
  echo "$n"
}

run_session() {
  local bank="$1" label="$2"
  local total
  total=$(load_bank "$bank") || return 1

  SESSION_LABEL="$label"
  SESSION_STARTED=1
  timer_start 3600

  local qorder
  mapfile -t qorder < <(shuffle_indices "$total")

  local n=0 quit=0 idx q stem correct d1 d2 d3 domain expl choice ok
  for idx in "${qorder[@]}"; do
    # Check the clock only between questions (per brief 6.2).
    if timer_expired; then
      echo
      read -r -p "${C_YELLOW}Time's up (60 min). Continue past the timer? (y/N): ${C_RESET}" ans
      if [[ "${ans,,}" == "y" ]]; then TIMER_OVERRIDE=1; else break; fi
    fi

    n=$(( n + 1 ))
    q=$(jq -c ".[$idx]" "$bank")
    stem=$(jq -r '.question' <<<"$q")
    correct=$(jq -r '.options.correct' <<<"$q")
    d1=$(jq -r '.options.distractor_1' <<<"$q")
    d2=$(jq -r '.options.distractor_2' <<<"$q")
    d3=$(jq -r '.options.distractor_3' <<<"$q")
    domain=$(jq -r '.domain' <<<"$q")
    expl=$(jq -r '.explanation' <<<"$q")

    # a) stem only  b) recall-first beat  c) options
    display_question "$n" "$total" "$(timer_remaining_min)" "$stem"
    read -r -p "${C_CYAN}Press Enter to see the options...${C_RESET}" _

    shuffle_options "$correct" "$d1" "$d2" "$d3"
    display_options "${SHUF_OPTS[0]}" "${SHUF_OPTS[1]}" "${SHUF_OPTS[2]}" "${SHUF_OPTS[3]}"

    # d/e) read + validate answer
    while true; do
      read -r -p "${C_CYAN}Your answer (A/B/C/D, or Q to quit): ${C_RESET}" choice
      choice="${choice^^}"
      case "$choice" in
        A|B|C|D) break ;;
        Q)       quit=1; break ;;
        *)       echo "    Please enter A, B, C, D, or Q." ;;
      esac
    done
    [[ "$quit" -eq 1 ]] && break

    # f/g) feedback + explanation
    ok=0
    [[ "$choice" == "$SHUF_CORRECT_LETTER" ]] && ok=1
    scoring_record "$domain" "$ok"
    display_feedback "$ok" "$SHUF_CORRECT_LETTER" "$expl"

    # h) advance
    echo
    read -r -p "${C_CYAN}Press Enter for the next question...${C_RESET}" _
  done

  display_clear
  scoring_results "$SESSION_LABEL" "$(timer_elapsed)"
}

main() {
  require_deps
  display_welcome
  display_menu
  local sel
  while true; do
    read -r -p "${C_CYAN}Choice (1/2/3/Q): ${C_RESET}" sel
    case "${sel^^}" in
      1) run_session "$QDIR/interview-1.json" "Interview 1" || exit 1; break ;;
      2) run_session "$QDIR/interview-2.json" "Interview 2" || exit 1; break ;;
      3) run_session "$QDIR/interview-3.json" "Interview 3" || exit 1; break ;;
      Q) echo "  Goodbye."; exit 0 ;;
      *) echo "    Please enter 1, 2, 3, or Q." ;;
    esac
  done
}

main "$@"
