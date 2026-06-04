# Solution — how the runner works

This is a drill, not a fix-it lab, so there are no "answers" to reveal here.
This document explains how the runner is built, for anyone maintaining it.

## Layout

```
lab-095-interview-drill-mcq/
├── runner.sh            # main loop: menu → session → results
├── lib/
│   ├── display.sh       # colours, screen chrome, question/option/feedback rendering
│   ├── timer.sh         # 60-minute session timer
│   ├── shuffle.sh       # question-order and A/B/C/D position shuffling
│   └── scoring.sh       # per-domain tallies and the results breakdown
├── validate.sh          # structural validation (brief §8.2)
├── questions/           # interview-{1,2,3}.json — the banks (read-only here)
├── CHALLENGE.md         # lab-runner metadata + scenario
├── README.md            # how to run + the `interview` shortcut
└── bashrc-snippet.sh    # the `interview` shell function
```

`runner.sh` resolves its own directory via `BASH_SOURCE`, so it works the same
whether invoked as `./runner.sh`, through `lab start 095`, or via the
`interview` shortcut — the cwd doesn't matter.

## Session flow (runner.sh)

1. `require_deps` checks `jq` and `shuf` are present.
2. Welcome screen + Interview 1/2/3 menu.
3. `run_session` loads the chosen bank, validating the JSON parses and is
   non-empty before starting (a missing or malformed bank errors out instead of
   starting a broken session).
4. The question order is shuffled once (`shuffle_indices`), then per question:
   stem is shown alone → Enter (the deliberate recall-first beat) → options are
   revealed in shuffled A/B/C/D order → answer is read and validated → immediate
   ✓/✗ feedback and explanation → Enter to advance.
5. The session ends when the bank is exhausted, the timer expires and the user
   declines to continue, or the user quits (`Q`). Results are always shown.

## Timer (lib/timer.sh)

The timer records a start epoch and computes elapsed/remaining time on demand.
The brief suggested a background writer process, but the runner only needs to
check the clock **between** questions, so an epoch diff is equivalent and avoids
orphan background processes and temp-file races on the Pi. `timer_expired`
returns false once the user opts to continue past 60 minutes (`TIMER_OVERRIDE`).

## Shuffling (lib/shuffle.sh)

Both the question order and the option positions use `shuf` with no fixed seed
(fresh randomness per session). For options, the four texts are loaded with the
correct answer always at input index 0; after shuffling, whichever display slot
received index 0 becomes the correct letter (`SHUF_CORRECT_LETTER`). Because the
JSON stores `correct`/`distractor_1..3` under named keys (never an indexed
array), there is no "answer is always C" leakage.

## Scoring (lib/scoring.sh)

Overall and per-domain correct/total counts are kept in associative arrays.
`scoring_results` prints the score, elapsed time, and a per-domain breakdown
with proportional `█`/`░` bars, plus the weakest and strongest domains. Domain
keys are mapped to display labels (e.g. `cicd` → `CI/CD`).

## Edge cases (brief §6.6)

- **Q at the answer prompt** — breaks the loop and shows partial results.
- **Ctrl+C** — trapped (`on_interrupt`); shows partial results if a session was
  running, then exits cleanly. `cleanup` (trap EXIT) restores the cursor.
- **Missing/malformed bank** — `load_bank` reports a clear error and the session
  never starts.
- **All questions answered before 60 min** — the loop ends and results show
  immediately.

## Lab-runner integration

`lab start 095` works because `labrunner.sh` gained a small opt-in hook: if a
lab directory has an executable `runner.sh` and its `CHALLENGE.md` `Category`
contains "Drill" or "Interview", the runner `exec`s `runner.sh` directly instead
of the fix-it dispatch. This is gated so no existing lab is affected.

## Validation (validate.sh)

Structural only: `jq` present; each bank parses and has 60-80 MCQs; every MCQ has
the required fields and exactly four named options; all four option texts within
an MCQ are distinct (so no duplicate distractor and the correct answer is never
reused as a distractor); `runner.sh` is executable and the `lib/*.sh` modules
exist. Functional grading is verified by the manual smoke test (brief §8.3).
