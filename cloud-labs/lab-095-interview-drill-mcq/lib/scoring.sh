#!/usr/bin/env bash
# scoring.sh — tracks correct/incorrect overall and per domain, renders results.
# Sourced by runner.sh.

declare -A SCORE_DOMAIN_TOTAL
declare -A SCORE_DOMAIN_CORRECT
SCORE_TOTAL=0
SCORE_CORRECT=0
SCORE_DOMAINS=""   # space-padded list, preserves first-seen order

# Pretty domain labels matching the brief's results layout.
scoring_label() {
  case "$1" in
    aws)        echo "AWS" ;;
    kubernetes) echo "Kubernetes" ;;
    cicd)       echo "CI/CD" ;;
    terraform)  echo "Terraform" ;;
    docker)     echo "Docker" ;;
    linux)      echo "Linux" ;;
    git)        echo "Git" ;;
    *)          echo "$1" ;;
  esac
}

# scoring_record <domain> <is_correct 1|0>
scoring_record() {
  local d="$1" ok="$2"
  SCORE_TOTAL=$(( SCORE_TOTAL + 1 ))
  SCORE_DOMAIN_TOTAL[$d]=$(( ${SCORE_DOMAIN_TOTAL[$d]:-0} + 1 ))
  if [[ "$ok" -eq 1 ]]; then
    SCORE_CORRECT=$(( SCORE_CORRECT + 1 ))
    SCORE_DOMAIN_CORRECT[$d]=$(( ${SCORE_DOMAIN_CORRECT[$d]:-0} + 1 ))
  fi
  [[ " $SCORE_DOMAINS " == *" $d "* ]] || SCORE_DOMAINS="$SCORE_DOMAINS $d"
}

# scoring_bar <pct> [width]  -> proportional █/░ bar
scoring_bar() {
  local pct="$1" width="${2:-11}" filled i bar=""
  filled=$(( (pct * width + 50) / 100 ))
  (( filled > width )) && filled=$width
  (( filled < 0 )) && filled=0
  for (( i = 0; i < filled; i++ )); do bar+="█"; done
  for (( i = filled; i < width; i++ )); do bar+="░"; done
  printf '%s' "$bar"
}

# scoring_results <interview_label> <elapsed_seconds>
scoring_results() {
  local label="$1" elapsed="$2"
  local pct=0
  (( SCORE_TOTAL > 0 )) && pct=$(( SCORE_CORRECT * 100 / SCORE_TOTAL ))
  local mins=$(( elapsed / 60 )) secs=$(( elapsed % 60 ))

  echo
  printf '%s%s%s\n' "$C_BOLD" "$DISPLAY_HEAVY" "$C_RESET"
  printf '%s                  %s — Results%s\n' "$C_BOLD" "$label" "$C_RESET"
  printf '%s%s%s\n\n' "$C_BOLD" "$DISPLAY_HEAVY" "$C_RESET"

  printf '  Score:        %d / %d    (%d%%)\n' "$SCORE_CORRECT" "$SCORE_TOTAL" "$pct"
  printf '  Time taken:   %d min %d sec\n\n' "$mins" "$secs"

  if [[ -z "${SCORE_DOMAINS// }" ]]; then
    echo "  No questions answered."
    echo
    return
  fi

  echo "  Domain breakdown:"
  local d c t dp weakest="" strongest="" weak_pct=101 strong_pct=-1 name
  for d in $SCORE_DOMAINS; do
    t=${SCORE_DOMAIN_TOTAL[$d]:-0}
    c=${SCORE_DOMAIN_CORRECT[$d]:-0}
    (( t == 0 )) && continue
    dp=$(( c * 100 / t ))
    name=$(scoring_label "$d")
    printf '    %-12s %s  %2d/%-3d (%d%%)\n' "$name" "$(scoring_bar "$dp")" "$c" "$t" "$dp"
    if (( dp < weak_pct ));   then weak_pct=$dp;   weakest="$name"; fi
    if (( dp > strong_pct )); then strong_pct=$dp; strongest="$name"; fi
  done
  echo
  printf '  Weakest area:   %s (%d%%)\n' "$weakest" "$weak_pct"
  printf '  Strongest area: %s (%d%%)\n' "$strongest" "$strong_pct"
  echo
}
