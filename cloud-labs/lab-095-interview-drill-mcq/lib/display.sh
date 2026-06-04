#!/usr/bin/env bash
# display.sh — terminal rendering: colours, question/options, feedback, chrome.
# No emoji (lab standard). Uses the ✓ / ✗ marks and block chars the brief specifies.
# Sourced by runner.sh; not executed directly.

# Colours only when stdout is a TTY (so piping/redirection stays clean).
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_CYAN=$'\033[36m'; C_YELLOW=$'\033[33m'
else
  C_RESET=''; C_BOLD=''; C_DIM=''; C_GREEN=''; C_RED=''; C_CYAN=''; C_YELLOW=''
fi

readonly DISPLAY_RULE="───────────────────────────────────────────────────────────"
readonly DISPLAY_HEAVY="═══════════════════════════════════════════════════════════"

display_clear() { clear 2>/dev/null || printf '\033[2J\033[H'; }

display_welcome() {
  display_clear
  printf '%s%s%s\n' "$C_BOLD" "$DISPLAY_HEAVY" "$C_RESET"
  printf '%s            Interview Drill — Multiple Choice%s\n' "$C_BOLD" "$C_RESET"
  printf '%s%s%s\n\n' "$C_BOLD" "$DISPLAY_HEAVY" "$C_RESET"
  echo "  A timed recall drill of common Cloud Engineer interview questions."
  echo
  echo "  Rules:"
  echo "    - Each session is 60 minutes (hard cap, with an option to continue)."
  echo "    - Each question shows the stem first; press Enter to reveal the options."
  echo "    - Answer A/B/C/D for immediate feedback and an explanation."
  echo "    - Press Q at the answer prompt to quit early and see partial results."
  echo
}

display_menu() {
  echo "  Select an interview bank:"
  echo "    1) Interview 1"
  echo "    2) Interview 2"
  echo "    3) Interview 3"
  echo "    Q) Quit"
  echo
}

# display_question <counter> <total> <remaining_min> <stem>
display_question() {
  display_clear
  printf '%sQuestion %s of %s  —  %s min remaining%s\n' "$C_CYAN" "$1" "$2" "$3" "$C_RESET"
  printf '%s%s%s\n\n' "$C_DIM" "$DISPLAY_RULE" "$C_RESET"
  printf '%s\n\n' "$4"
}

# display_options <A> <B> <C> <D>  (printed below the stem; screen not cleared)
display_options() {
  local letters=(A B C D) i texts=("$1" "$2" "$3" "$4")
  for i in 0 1 2 3; do
    printf '    %s)  %s\n' "${letters[$i]}" "${texts[$i]}"
  done
  echo
}

# display_feedback <is_correct 1|0> <correct_letter> <explanation>
display_feedback() {
  echo
  if [[ "$1" -eq 1 ]]; then
    printf '%s%s✓ Correct%s\n\n' "$C_BOLD" "$C_GREEN" "$C_RESET"
  else
    printf '%s%s✗ Incorrect — the answer was %s%s\n\n' "$C_BOLD" "$C_RED" "$2" "$C_RESET"
  fi
  printf '%sExplanation:%s %s\n' "$C_BOLD" "$C_RESET" "$3"
}
