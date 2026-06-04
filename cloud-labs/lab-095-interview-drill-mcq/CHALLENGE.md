Title: Interview Drill (Multiple Choice)
Difficulty: N/A (timed drill, not a fix-it lab)
Time: 60 minutes per session
Category: Interview Prep / MCQ Drill
Skills: Rapid recall under time pressure, MCQ exam technique, weak-domain identification

## Scenario

This is not a Build → Break → Fix lab. It is a timed, multiple-choice recall
drill over 200+ of the most common Cloud Engineer interview questions, balanced
across AWS, Kubernetes, CI/CD, Terraform, Docker, Linux, and Git.

You pick one of three Interview banks (~70 questions each) and sit a 60-minute
session. Each question shows the stem first — you try to answer in your head —
then you press Enter to reveal the A/B/C/D options. You get immediate feedback
and an explanation, and a domain breakdown of your strong and weak areas at the
end. Option positions are shuffled per question, so the answer is never "always C".

## What You'll Practise

- Rapid recall of Cloud Engineer interview concepts under time pressure
- MCQ exam technique (Solutions Architect-style pattern breaking)
- Identifying weak domains via the post-session breakdown
- Building interview muscle without needing a human interviewer

## How to Use This Lab

Launch the drill any of these ways (they all run the same code):

```bash
lab start 095        # via the lab runner (this CHALLENGE.md)
./runner.sh          # directly, from this lab directory
interview            # the optional shortcut (see README.md to install)
```

Pick Interview 1, 2, or 3 at the menu. Press Q at the answer prompt to quit
early and still see partial results. Ctrl+C also exits cleanly with partial
results.

## Validation

Structural validation (banks well-formed, scripts in place):

```bash
./validate.sh
```

Functional checking is the manual smoke test in the brief (section 8.3) —
run a session and confirm shuffling, feedback, the timer, and the breakdown.
