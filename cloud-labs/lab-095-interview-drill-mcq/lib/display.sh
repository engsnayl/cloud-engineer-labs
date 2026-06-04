#!/usr/bin/env bash
# display.sh — terminal rendering: colours, screen chrome, question/option/feedback.
# No emoji (lab standard). Uses the ✓ / ✗ marks and block chars the brief specifies.
# Sourced by runner.sh; not executed directly. Rendering only — no session logic.

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

# Wrap width: min(terminal columns, 90), with a sane floor. 90 keeps reading
# width comfortable; capping to the terminal avoids overflow on narrow windows.
display_wrap_width() {
  local cols=90 tc
  if [[ -t 1 ]]; then
    tc=$(tput cols 2>/dev/null || echo 90)
    [[ "$tc" =~ ^[0-9]+$ ]] || tc=90
    (( tc < cols )) && cols=$tc
  fi
  (( cols < 40 )) && cols=40
  echo "$cols"
}

# print_paragraphs <text>
# Splits prose into one paragraph per sentence (blank line between), word-wrapping
# each. Protects e.g./i.e. (always mid-sentence) and "etc." followed by a lowercase
# word, so those periods are not mistaken for sentence boundaries. Sentences that
# legitimately start with a lowercase tool name (e.g. "journalctl's ...") still
# break correctly, because suppression is by abbreviation, not by next-char case.
# _sentence_split <text>  -> one sentence per line (abbreviation-protected).
_sentence_split() {
  local SP=$'\001'
  printf '%s\n' "$1" \
    | sed -E "s/(e\.g\.|i\.e\.) /\1${SP}/g; s/(etc\.) ([a-z])/\1${SP}\2/g" \
    | sed -E 's/([.!?]) +/\1\n/g' \
    | sed "s/${SP}/ /g"
}

# _wrap_paragraphs  -> reads sentences on stdin; wraps each, blank line between.
_wrap_paragraphs() {
  local w line
  w=$(display_wrap_width)
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    printf '%s\n' "$line" | fold -s -w "$w"
    echo
  done
}

print_paragraphs() { _sentence_split "$1" | _wrap_paragraphs; }

# print_explanation <relabeled_text>
# Like print_paragraphs, but sentences that begin with an "(A|B|C|D)" option
# reference are reordered into ascending letter order within their own slots, so
# the explanation walks the options A->D rather than JSON storage order. Non-ref
# sentences (the preamble) keep their positions.
print_explanation() {
  local lines=() line
  while IFS= read -r line; do [[ -n "$line" ]] && lines+=("$line"); done < <(_sentence_split "$1")
  local i refslots=() keys=() re='^\(([ABCD])\)'
  for i in "${!lines[@]}"; do
    if [[ "${lines[$i]}" =~ $re ]]; then
      refslots+=("$i")
      keys+=("${BASH_REMATCH[1]}|$i")
    fi
  done
  if (( ${#refslots[@]} > 1 )); then
    local sorted=() entry slot k=0 s
    while IFS= read -r entry; do
      slot="${entry#*|}"
      sorted+=("${lines[$slot]}")
    done < <(printf '%s\n' "${keys[@]}" | sort)
    for s in "${refslots[@]}"; do
      lines[$s]="${sorted[$k]}"
      k=$(( k + 1 ))
    done
  fi
  printf '%s\n' "${lines[@]}" | _wrap_paragraphs
}

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
  print_paragraphs "$4"
}

# display_options <A> <B> <C> <D>  (printed below the stem; screen not cleared)
# Each option is word-wrapped with a hanging indent, and separated by a blank line.
display_options() {
  local letters=(A B C D) texts=("$1" "$2" "$3" "$4")
  local w body_w i first ln
  w=$(display_wrap_width)
  body_w=$(( w - 8 )); (( body_w < 20 )) && body_w=20
  for i in 0 1 2 3; do
    first=1
    while IFS= read -r ln; do
      if (( first )); then
        printf '    %s)  %s\n' "${letters[$i]}" "$ln"
        first=0
      else
        printf '        %s\n' "$ln"
      fi
    done < <(printf '%s\n' "${texts[$i]}" | fold -s -w "$body_w")
    echo
  done
}

# explanation_relabel <explanation> <d1_letter> <d2_letter> <d3_letter>
# Rewrites the storage-order labels "Distractor 1/2/3" (and the plural form) to
# the parenthesised A/B/C/D letter each distractor landed at after shuffling, so
# the explanation matches what the reader saw. The banks keep "Distractor N" as
# the authoring label; this is a render-time substitution only.
explanation_relabel() {
  local t="$1" l1="$2" l2="$3" l3="$4"
  t="${t//Distractors 1/($l1)}"; t="${t//Distractor 1/($l1)}"
  t="${t//Distractors 2/($l2)}"; t="${t//Distractor 2/($l2)}"
  t="${t//Distractors 3/($l3)}"; t="${t//Distractor 3/($l3)}"
  printf '%s' "$t"
}

# display_feedback <is_correct 1|0> <correct_letter> <d1_letter> <d2_letter> <d3_letter> <explanation>
display_feedback() {
  echo
  if [[ "$1" -eq 1 ]]; then
    printf '%s%s✓ Correct%s\n\n' "$C_BOLD" "$C_GREEN" "$C_RESET"
  else
    printf '%s%s✗ Incorrect — the answer was %s%s\n\n' "$C_BOLD" "$C_RED" "$2" "$C_RESET"
  fi
  printf '%sExplanation:%s\n' "$C_BOLD" "$C_RESET"
  print_explanation "$(explanation_relabel "$6" "$3" "$4" "$5")"
}
