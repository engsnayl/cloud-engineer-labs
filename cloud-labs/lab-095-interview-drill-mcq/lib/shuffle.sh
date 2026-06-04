#!/usr/bin/env bash
# shuffle.sh — randomise question order and A/B/C/D option positions.
# Uses shuf (coreutils, present on the Pi). No fixed seed: fresh randomness
# per session is intended. Sourced by runner.sh.

# shuffle_indices <count>  ->  prints 0..count-1 in random order, one per line
shuffle_indices() {
  local count="$1"
  (( count > 0 )) || return 0
  seq 0 $(( count - 1 )) | shuf
}

# shuffle_options <correct> <distractor_1> <distractor_2> <distractor_3>
# Populates globals:
#   SHUF_OPTS[0..3]        the four option texts in display (A,B,C,D) order
#   SHUF_LETTER[0..3]      storage-key index -> display letter, where index
#                          0=correct, 1=distractor_1, 2=distractor_2, 3=distractor_3
#   SHUF_CORRECT_LETTER    which of A/B/C/D now holds the correct answer
# Inputs are passed in storage order (correct first), so the input index is the
# storage key and SHUF_LETTER maps it to the letter that key landed at.
shuffle_options() {
  local opts=("$1" "$2" "$3" "$4")
  local letters=(A B C D)
  SHUF_OPTS=()
  SHUF_LETTER=()
  SHUF_CORRECT_LETTER=""
  local pos=0 idx
  while read -r idx; do
    SHUF_OPTS+=("${opts[$idx]}")
    SHUF_LETTER[$idx]="${letters[$pos]}"
    pos=$(( pos + 1 ))
  done < <(printf '%s\n' 0 1 2 3 | shuf)
  SHUF_CORRECT_LETTER="${SHUF_LETTER[0]}"
}
