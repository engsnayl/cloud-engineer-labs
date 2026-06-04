# Lab 095: Interview Drill (Multiple Choice)

A timed MCQ drill of the 100+ most common Cloud Engineer interview questions.
Three Interview banks of ~70 questions each, balanced across AWS, Kubernetes,
CI/CD, Terraform, Docker, Linux, and Git (208 MCQs total).

## How to run

```bash
lab start 095
```

You'll be prompted to select Interview 1, 2, or 3. Each session is 60 minutes
with a hard cap (with an option to continue past the timer to finish the
remaining questions).

Equivalent direct launch from this directory:

```bash
./runner.sh
```

### Optional: the `interview` shortcut

To launch the drill from anywhere by typing `interview`, install the snippet in
`bashrc-snippet.sh` into your shell:

```bash
cat cloud-labs/lab-095-interview-drill-mcq/bashrc-snippet.sh >> ~/.bashrc
source ~/.bashrc
```

The shortcut assumes the repo lives at `~/cloud-engineer-labs`. If it's
elsewhere, set the path once before sourcing:

```bash
echo 'export CLOUD_LABS_REPO="$HOME/path/to/cloud-engineer-labs"' >> ~/.bashrc
```

`interview` runs the exact same `runner.sh` as `lab start 095` — it's just a
faster entry point.

## What the drill does

- Presents one question at a time, **stem first**
- Press Enter to reveal A/B/C/D options (the recall-first beat — try to answer
  in your head before the options appear)
- Type your answer; get immediate feedback and an explanation
- A/B/C/D positions are shuffled per question, so the answer is never "always C"
- Session ends after 60 minutes, when you complete all questions, or when you
  quit (Q) — Ctrl+C also exits cleanly
- End-of-session: score plus a domain breakdown showing your strong and weak areas

## Requirements

- `bash`, `jq`, and `shuf` (GNU coreutils) — all present on the Pi by default.
  On a fresh box: `sudo apt-get install -y jq coreutils`.

## Validation

```bash
./validate.sh
```

Confirms all three banks are well-formed (parse, counts, required fields,
exactly four distinct options per MCQ) and the runner scripts are in place.
This is structural only; functional behaviour is verified by the manual smoke
test (brief section 8.3).

## Source material

All questions derive from `Interview-Prep-Combined.md` (the interview-prep-app
repo). Two MCQs per source question, distributed across the three banks. The
banks were authored and quality-reviewed in a separate phase; this lab is the
runner over them.

## Why this lab exists

Reading the prep markdown is passive. Being timed and graded on multiple choice
forces actual recall under interview-like pressure, and the domain breakdown
tells you where to focus next.
