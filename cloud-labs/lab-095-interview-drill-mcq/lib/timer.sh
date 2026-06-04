#!/usr/bin/env bash
# timer.sh — 60-minute session timer.
# Implemented as an elapsed-time calculation from a recorded start epoch rather
# than a background writer process: the runner only needs to check the clock
# BETWEEN questions (per brief 6.2), and epoch-diff avoids orphan processes and
# temp-file races on the Pi. Sourced by runner.sh.

TIMER_START=0
TIMER_LIMIT=3600
TIMER_OVERRIDE=0   # set to 1 once the user accepts "continue past the timer"

# timer_start [limit_seconds]
timer_start() {
  TIMER_START=$(date +%s)
  TIMER_LIMIT="${1:-3600}"
  TIMER_OVERRIDE=0
}

timer_elapsed() { echo $(( $(date +%s) - TIMER_START )); }

timer_remaining() {
  local r=$(( TIMER_LIMIT - $(timer_elapsed) ))
  (( r < 0 )) && r=0
  echo "$r"
}

# Whole minutes remaining, rounded up so "0 min remaining" only shows at expiry.
timer_remaining_min() {
  local r; r=$(timer_remaining)
  echo $(( (r + 59) / 60 ))
}

# Returns success (0) when the limit has passed and the override is not set.
timer_expired() {
  [[ "$TIMER_OVERRIDE" -eq 1 ]] && return 1
  (( $(timer_elapsed) >= TIMER_LIMIT ))
}
