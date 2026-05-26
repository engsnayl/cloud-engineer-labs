# Lab Build Brief: Interview Drill Runner (MCQ)

**Purpose:** A multiple-choice interview drill lab that tests the most common Cloud Engineer interview questions, sourced from `Interview-Prep-Combined.md`. Matches the pattern of the existing Linux and Git command drills, but for conceptual interview prep rather than command recall.

**Audience for this brief:** Claude Code, executing on Stephen's Raspberry Pi 5 (`~/cloud-engineer-labs`).

**Authoring standard:** Solutions Architect Associate exam-level difficulty. Distractor quality is the make-or-break of this lab — see Section 4.

---

## 1. Lab scope

### 1.1 What this lab is

A terminal-based MCQ drill, run via the existing `lab` runner pattern. Stephen selects one of three "Interviews" (banks of ~70 MCQs each), sits a 60-minute timed session, and gets immediate per-question feedback plus a domain-breakdown results summary at the end.

### 1.2 What this lab is NOT

- Not a flashcard app — questions are MCQ, not open recall
- Not a study mode (no "show me the answer" cheat) — Stephen has the source `.md` for study
- Not persistent across sessions — no progress saved between runs, no leaderboard, no streak tracking. Each session is self-contained.
- Not a behavioural prep tool — the 6 behavioural questions in the source are excluded (not MCQ-friendly)

### 1.3 Lab metadata

```
Lab number: [next available — likely 088 or current sequence head]
Name: Interview Drill (Multiple Choice)
Domain: Interview Prep
Difficulty: N/A (drill, not a fix-it lab)
Duration: 60 minutes per session (hard cap with override prompt)
```

This is **not** a Build → Break → Fix lab. It has no `validate.sh` in the traditional sense (no broken state to fix). Instead, validation is "does the runner execute, do all questions render correctly, does the timer fire."

---

## 2. Source material

**Input file:** `Interview-Prep-Combined.md`, located in a separate repo:

- GitHub: https://github.com/engsnayl/interview-prep-app/blob/main/Interview-Prep-Combined.md
- Raw URL: https://raw.githubusercontent.com/engsnayl/interview-prep-app/main/Interview-Prep-Combined.md
- Local path (if cloned to Pi): `~/interview-prep-app/Interview-Prep-Combined.md`

Claude Code should clone the repo or fetch the raw file directly. The file contains 110 questions across 8 domains.

**Domain distribution after excluding behavioural:**

| Domain     | Source questions | MCQs at 2× | Approx per bank |
|------------|------------------|------------|-----------------|
| AWS        | 28               | 56         | ~19             |
| Kubernetes | 22               | 44         | ~15             |
| CI/CD      | 18               | 36         | ~12             |
| Terraform  | 13               | 26         | ~9              |
| Docker     | 10               | 20         | ~7              |
| Linux      | 7                | 14         | ~5              |
| Git        | 6                | 12         | ~4              |
| **Total**  | **104**          | **208**    | **~69**         |

Target: **2 MCQs per source question** → ~208 MCQs, split into 3 banks of ~69 each (Interview 1, 2, 3).

**Behavioural exclusion:** beh-001 through beh-006 are excluded entirely. They are narrative STAR-format answers and cannot be made MCQ without trivialising them.

---

## 3. Bank composition

### 3.1 Strategy: Balanced domain mix

Each of the 3 Interview banks must contain a **proportional mix of all 7 domains**, so each Interview feels like a real generalist Cloud Engineer screen.

**Target composition per bank (~69 questions each):**

| Domain     | Per bank |
|------------|----------|
| AWS        | 18-19    |
| Kubernetes | 14-15    |
| CI/CD      | 12       |
| Terraform  | 8-9      |
| Docker     | 6-7      |
| Linux      | 4-5      |
| Git        | 4        |
| **Total**  | **~69**  |

### 3.2 How to split source questions across banks

For each source question, **2 MCQs are generated** (covering different facets of the source — e.g. aws-002 could yield one MCQ on "what defines public/private" and one on "NAT Gateway vs IGW placement").

**Distribution rule:** the 2 MCQs from one source go into **different banks** wherever possible. This prevents any single Interview from being "all questions about a topic Stephen happens to know cold."

**Priority weighting:** within each bank, ensure `priority: critical` and `priority: high` source questions are represented. `priority: low` (only 2 in the source) can be assigned freely.

### 3.3 Bank labelling

```
Interview 1: General Cloud Engineering Screen (balanced)
Interview 2: General Cloud Engineering Screen (balanced)
Interview 3: General Cloud Engineering Screen (balanced)
```

All three are equivalent in difficulty and domain coverage. Stephen picks one per session; running the same one twice is fine (questions present in random order, A/B/C/D shuffled per run, so it's not pure pattern recall).

---

## 4. MCQ authoring rubric — NON-NEGOTIABLE

**This is the most important section of the brief.** Bad distractors make the whole lab useless.

### 4.1 Difficulty target

**AWS Solutions Architect Associate exam level.** Distractors must be plausibly correct to someone with surface-level knowledge but wrong on closer inspection. A candidate who has *memorised keywords* should fail; a candidate who *understands the concept* should pass.

### 4.2 Distractor pattern requirements

For every MCQ, the 3 distractors must collectively use at least 2 of these patterns. Don't use the same pattern 3 times.

| Pattern | Description | Example |
|---------|-------------|---------|
| **Real concept, wrong context** | A genuine AWS/K8s/TF feature that doesn't answer this specific question | "MapPublicIpOnLaunch" as a distractor for "what makes a subnet public" |
| **Symmetric-but-wrong** | A clean-sounding parallel answer that's tidier than reality | "Throttled on both CPU and memory" when memory is actually OOMKilled |
| **Half-remembered version** | What a candidate would say if they got the concept 80% right | "OOMKilled immediately on both" |
| **What-would-happen-without-X** | The behaviour you'd see if a safety mechanism wasn't present (when the Q is about the safety mechanism) | "State silently overwrites" as a distractor for a question about state locking |
| **Adjacent technology confusion** | A correct answer for a similar-but-different service | "Lambda cold start mitigation" as a distractor for an ECS scaling question |

### 4.3 Things to NEVER do

- **"All of the above" / "None of the above"** — never used. They're a crutch and not exam-grade.
- **Absolutes as giveaways** — "always," "never," "100%" in distractors. Strong language signals wrongness, which is a tell.
- **Right answer is always the longest** — vary the length. Sometimes the right answer is short and precise.
- **Right answer is always the most technical-sounding** — sometimes simplicity wins; mix it up.
- **Trick questions** — distinct from hard questions. Don't depend on misreading the prompt or spotting a typo.
- **Outdated content** — no questions about Classic Load Balancer being recommended, `kubectl run --restart=Never` for pods, Terraform 0.11 syntax, Docker Swarm. If the source mentions deprecated tech, the MCQ tests "what's current," not "what used to be."

### 4.4 Question stem requirements

- **Single clear question** — no two-part questions ("What is X and how does Y work?")
- **Scenario-based where possible** — "A pod has requests X and limits Y; what happens when..." beats "What is the difference between requests and limits?"
- **Realistic scenarios** — use the kinds of situations a Cloud Engineer actually encounters, not contrived ones
- **No ambiguity** — exactly one defensibly correct answer. If two answers could both be right depending on interpretation, rewrite the stem.

### 4.5 Explanation requirements

Every MCQ needs an explanation that:

1. States the correct answer in one sentence
2. Explains **why each distractor is wrong** (not just why the right answer is right)
3. Adds one piece of real-world context (when this matters, common pitfall, related concept)
4. Stays under ~120 words total — this displays in the terminal, not a textbook

### 4.6 Worked examples (the bar to hit)

See **Appendix A** at the end of this brief. Three fully-authored sample MCQs covering AWS networking, Kubernetes resource limits, and Terraform state. Match this quality bar across all 208 MCQs.

### 4.7 Self-review before considering authoring done

For each MCQ, ask:
- Could a Solutions Architect Associate candidate plausibly pick any of the distractors? If no for any → rewrite that distractor.
- Is the right answer "obviously" longer, more technical, or more keyword-stuffed than the distractors? If yes → rebalance.
- Does the explanation explain why the *wrong* answers are wrong? If no → add this.
- Does this test understanding or just keyword recall? If just keyword → rewrite as a scenario.

---

## 5. Question bank format

### 5.1 File structure

```
cloud-labs/project-XXX-interview-drill/
├── README.md
├── CHALLENGE.md
├── SOLUTION.md                  # explains how the runner works, not "answers"
├── questions/
│   ├── interview-1.json
│   ├── interview-2.json
│   └── interview-3.json
├── runner.sh                    # the main drill loop
├── lib/
│   ├── timer.sh                 # 60-minute countdown logic
│   ├── shuffle.sh               # randomise question order and A/B/C/D positions
│   ├── scoring.sh               # tracks correct/incorrect, builds domain breakdown
│   └── display.sh               # terminal rendering, colours, recall-then-options flow
└── validate.sh                  # smoke test (see section 8)
```

### 5.2 JSON schema (one entry per MCQ)

```json
{
  "id": "aws-002-mcq-1",
  "source_id": "aws-002",
  "domain": "aws",
  "subdomain": "networking",
  "priority": "high",
  "difficulty": "easy",
  "question": "What technically distinguishes a public subnet from a private subnet in an AWS VPC?",
  "options": {
    "correct": "The subnet has a route in its route table sending 0.0.0.0/0 to an Internet Gateway",
    "distractor_1": "The subnet's CIDR block is within the VPC's public IP range",
    "distractor_2": "Instances launched in the subnet automatically receive a public IP address",
    "distractor_3": "The subnet is associated with a security group that allows inbound traffic from 0.0.0.0/0"
  },
  "explanation": "Nothing about a subnet is intrinsically 'public' or 'private' — the distinction is purely the route table. Auto-assign public IP is a separate, additive setting (an instance needs both the IGW route AND a public IP to be reachable). CIDR blocks within a VPC don't have public/private categories. Security groups operate at the instance level and don't define subnet type."
}
```

**Notes on the schema:**

- `correct` and `distractors` are stored under named keys, not as an indexed array. The runner shuffles them into A/B/C/D positions at display time — so storage order is meaningless and there's no "the answer is always C" leakage risk.
- `id` is unique. `source_id` lets the runner trace back to the original source question if Stephen wants to dig deeper.
- `domain` is lowercase and matches the source folder names: `aws`, `kubernetes`, `cicd`, `terraform`, `docker`, `linux`, `git`.
- `priority` and `difficulty` are passed through from source — not used by the runner but useful for future bank rebalancing.

### 5.3 File sizing

- Each `interview-N.json` file: roughly 69 entries
- One JSON array per file, no wrapper object
- Pretty-printed (2-space indent) for git diff readability

---

## 6. Runner specification

### 6.1 Invocation

```bash
lab <number>                    # launches the runner, presents Interview 1/2/3 menu
```

No command-line arguments. Interview selection happens interactively. This matches the existing lab runner pattern (no flags).

### 6.2 Session flow

```
1. Welcome screen — explain rules briefly, show Interview 1/2/3 choice
2. Interview selected — load JSON, shuffle question order, start 60-min timer
3. PER QUESTION:
   a. Display question stem only (no options yet)
   b. Prompt: "Press Enter to see options" — recall-first beat
   c. Display options A/B/C/D (shuffled positions, NOT stored order)
   d. Prompt: "Your answer (A/B/C/D, or Q to quit session):"
   e. Validate input — re-prompt on invalid (allow uppercase or lowercase)
   f. IMMEDIATE feedback: "✓ Correct" or "✗ Incorrect — answer was [X]"
   g. Display explanation
   h. Prompt: "Press Enter for next question"
4. Timer fires at 60 min:
   - If mid-question: complete the current question, then offer "Continue past timer? (y/N)"
   - If between questions: offer "Continue past timer? (y/N)" immediately
5. Session end (timer expired + declined continue, OR all questions done, OR user quit):
   - Display results summary (see 6.5)
```

### 6.3 Display rules

- Terminal colours: green for correct, red for incorrect, cyan for prompts, default for question text. Match the existing Linux/Git drill colour scheme if there's an established pattern.
- No emoji (per lab design standards — keep professional).
- Clear screen between questions (`clear` command) so previous answer doesn't linger.
- Question counter visible: e.g. `Question 12 of 69 — 47 min remaining`.

### 6.4 Recall-first flow

The "press Enter to see options" beat is **deliberate** — it's the muscle this lab is training. The candidate should be trying to answer in their head before the MCQ scaffolding kicks in. Don't shortcut this even if it feels slow during testing.

### 6.5 End-of-session results

```
═══════════════════════════════════════════════════════════
                  Interview 2 — Results
═══════════════════════════════════════════════════════════

  Score:        42 / 69    (61%)
  Time taken:   58 min 14 sec

  Domain breakdown:
    AWS          ████████░░░  14/19  (74%)
    Kubernetes   ███████░░░░  10/15  (67%)
    CI/CD        █████░░░░░░   6/12  (50%)
    Terraform    █████░░░░░░   4/8   (50%)
    Docker       ████░░░░░░░   3/7   (43%)
    Linux        ██████░░░░░   3/5   (60%)
    Git          ████░░░░░░░   2/4   (50%)

  Weakest area: Docker (43%)
  Strongest area: AWS (74%)
```

**Domain breakdown** is the only end-of-session detail required (per your earlier decision — no list of wrong-answer questions, no historical comparison).

The ASCII bar chart can be simple — proportional `█` characters scaled to 10-12 chars wide. If this is fiddly in bash, a plain numeric breakdown is acceptable.

### 6.6 Edge cases

- **Quit mid-session (Q):** show partial results based on questions answered so far. Don't crash.
- **Ctrl+C:** trap the signal, show partial results, exit cleanly. Don't leave the terminal in a weird state.
- **Bank JSON missing or malformed:** show clear error, don't start the session.
- **All questions answered before 60 min:** end session immediately, show results. Don't make Stephen wait.

---

## 7. Implementation notes

### 7.1 Language and tooling

- **Bash** for the runner — match the existing Linux/Git drill pattern.
- **`jq`** for JSON parsing — verify it's installed on the Pi (it should be).
- **No Python dependencies** unless absolutely necessary. Bash + `jq` should cover this.
- **No external libraries** — pure bash, no `npm install` or `pip install` required to run.

### 7.2 Randomisation

- Shuffle question order per session: use `shuf` (GNU coreutils, present on the Pi).
- Shuffle A/B/C/D positions per question: small bash function, store correct position internally, present in shuffled order.
- Seed: don't fix a seed — true randomness per session is what we want.

### 7.3 Timer

- Background process tracking elapsed time, written to a temp file every 5 seconds.
- Main loop checks elapsed time between questions.
- Timer override: if user accepts "continue past timer," set a flag and stop checking.
- Clean up the timer process on exit (trap EXIT).

### 7.4 Question authoring workflow (Claude Code's job)

**Recommended sequence:**

1. Parse `Interview-Prep-Combined.md` into structured per-source data
2. For each source (excluding behavioural), draft 2 MCQs against the rubric in section 4
3. **Self-review pass** — apply section 4.7 checklist to each MCQ
4. Distribute 208 MCQs across 3 banks per section 3.2 rules
5. Validate JSON schema for each file
6. Build the runner scripts
7. Smoke-test (see section 8) before declaring done

**Critical:** do NOT generate all 208 MCQs in one go without showing samples first. After authoring the first ~10 MCQs across 3-4 domains, **pause and surface them to Stephen for quality check** before continuing. This is the iteration loop that prevents shipping 200 weak MCQs.

### 7.5 Pi-specific gotchas

- ARM64 architecture — no x86-only tools
- `lsof -i :PORT` needs space before colon
- No `act` (incompatible with ARM64) — fine, this lab doesn't need it
- `nano` available as fallback editor over SSH (Ctrl+O → Enter → Ctrl+X to save)
- Stephen edits files via GitHub web → `git pull` to Pi, so Claude Code's job is to write files locally on the Pi and commit + push them; Stephen reviews on GitHub

---

## 8. Validation

### 8.1 What "done" looks like

- [ ] All 3 JSON banks exist, each with ~69 valid MCQs
- [ ] Each MCQ has exactly 4 options (1 correct + 3 distractors), explanation, and metadata
- [ ] JSON parses cleanly with `jq` for all 3 files
- [ ] Runner launches via `lab <number>` and presents Interview menu
- [ ] Selecting an Interview shuffles question order
- [ ] Each question displays stem first, then options on Enter
- [ ] A/B/C/D positions are shuffled per question (verify by running same Interview twice and checking the correct answer isn't always C)
- [ ] Immediate feedback shows on submit
- [ ] Timer fires at 60 min and offers continue prompt
- [ ] Results screen shows score + domain breakdown
- [ ] Quit mid-session shows partial results without crashing
- [ ] All 3 Interviews can be completed end-to-end without errors

### 8.2 `validate.sh` for this lab

Unlike Build → Break → Fix labs, there's no broken state. The validate script for this lab should:

1. Check `jq` is installed
2. Parse all 3 JSON files with `jq` and confirm count is in range (60-80 per bank)
3. Check each MCQ has all required fields
4. Check each MCQ has exactly 4 options
5. Check no two distractors are identical within a single MCQ
6. Check no MCQ has the correct answer also appearing as a distractor
7. Confirm `runner.sh` is executable
8. Confirm `lib/*.sh` scripts exist

This is structural validation, not "does it grade correctly" — that's manual smoke-testing by Stephen.

### 8.3 Manual smoke test for Stephen (post-build)

1. Run `lab <number>` → pick Interview 1 → answer 3 questions → quit → verify partial results
2. Run again → pick Interview 1 → confirm questions appear in different order
3. Confirm same Interview but A/B/C/D positions differ between runs (correct answer isn't always C)
4. Pick Interview 2 → let timer expire → verify continue prompt works
5. Complete a full session → verify domain breakdown reflects answers correctly

---

## 9. README and CHALLENGE templates

### 9.1 README.md

```markdown
# Project XXX: Interview Drill (Multiple Choice)

A timed MCQ drill of the 100+ most common Cloud Engineer interview questions. Three Interview banks of ~70 questions each, balanced across AWS, Kubernetes, CI/CD, Terraform, Docker, Linux, and Git.

## How to run

\`\`\`bash
lab XXX
\`\`\`

You'll be prompted to select Interview 1, 2, or 3. Each session is 60 minutes with a hard cap (with an option to continue past the timer to finish remaining questions).

## What the drill does

- Presents one question at a time, stem first
- Press Enter to reveal A/B/C/D options (recall-first beat)
- Type your answer; get immediate feedback + explanation
- Session ends after 60 min, or when you complete all questions, or when you quit
- End-of-session: score + domain breakdown showing strong/weak areas

## Source material

All questions derive from `Interview-Prep-Combined.md` in the parent repo's `Interview Prep App` directory. Two MCQs per source question, distributed across three banks.

## Why this lab exists

Interview prep needs friction. Reading the prep markdown is passive; being timed and graded on multiple-choice forces actual recall under interview-like pressure.
```

### 9.2 CHALLENGE.md (uses the bare metadata format per lab standards)

```markdown
Lab: 0XX
Name: Interview Drill (Multiple Choice)
Domain: Interview Prep
Difficulty: N/A
Duration: 60 minutes per session

## What You'll Practise

- Rapid recall of Cloud Engineer interview concepts under time pressure
- Pattern-breaking for MCQ exam preparation (Solutions Architect-style)
- Identifying weak domains via post-session breakdown
- Building interview muscle without needing a human interviewer
```

---

## 10. Out of scope

These are intentionally NOT included in this build. Stephen has already considered and deferred them:

- Persistent scoring across sessions (no streak, no history)
- Wrong-answer review at session end (just the breakdown)
- Spaced repetition (resurface questions you got wrong)
- Difficulty progression (foundational → advanced banks)
- Behavioural question coverage (excluded — not MCQ-friendly)
- Visual feedback beyond terminal colours (no GUI, no web)
- Mobile/remote access (terminal-only on the Pi)

---

# Appendix A — Sample MCQs (the quality bar)

These three MCQs are the **floor**, not the ceiling, of quality for the 208 you'll author. If a generated MCQ feels weaker than these, rewrite it.

---

### Sample 1 — aws-002 (public vs private subnets)

```json
{
  "id": "aws-002-mcq-1",
  "source_id": "aws-002",
  "domain": "aws",
  "subdomain": "networking",
  "priority": "high",
  "difficulty": "easy",
  "question": "What technically distinguishes a public subnet from a private subnet in an AWS VPC?",
  "options": {
    "correct": "The subnet has a route in its route table sending 0.0.0.0/0 to an Internet Gateway",
    "distractor_1": "The subnet's CIDR block is within the VPC's public IP range",
    "distractor_2": "Instances launched in the subnet automatically receive a public IP address",
    "distractor_3": "The subnet is associated with a security group that allows inbound traffic from 0.0.0.0/0"
  },
  "explanation": "Nothing about a subnet is intrinsically public or private — the distinction is purely the route table. Auto-assign public IP (distractor 2) is a real, separate setting (MapPublicIpOnLaunch) but an instance needs BOTH the IGW route AND a public IP to be reachable. CIDR blocks within a VPC aren't categorised as public or private. Security groups operate at the instance level and never define subnet type."
}
```

**Why this is the bar:**
- Distractor 2 is a real AWS feature in a wrong context (the trap)
- Distractor 1 sounds plausible but conflates concepts
- Distractor 3 confuses subnet routing with instance-level firewalling
- Explanation explains why each distractor fails

---

### Sample 2 — k8s-005 (requests vs limits)

```json
{
  "id": "k8s-005-mcq-1",
  "source_id": "k8s-005",
  "domain": "kubernetes",
  "subdomain": "resources",
  "priority": "high",
  "difficulty": "medium",
  "question": "A pod has cpu requests: 200m, limits: 500m and memory requests: 256Mi, limits: 512Mi. The pod tries to use 600m of CPU and 600Mi of memory. What happens?",
  "options": {
    "correct": "The pod is throttled on CPU and OOMKilled on memory",
    "distractor_1": "The pod is OOMKilled immediately on both CPU and memory",
    "distractor_2": "The pod is throttled on CPU and throttled on memory",
    "distractor_3": "The pod is allowed to burst on both since the node has spare capacity"
  },
  "explanation": "CPU is a compressible resource — exceeding the limit results in throttling, not termination. Memory is incompressible — exceeding the limit results in the kernel OOM-killing the container. Distractor 1 is the half-remembered 'limits = killed' rule without nuance. Distractor 2 is symmetric but wrong (memory doesn't throttle). Distractor 3 describes how requests behave when the node has spare capacity, not limits — a real concept, wrong context."
}
```

**Why this is the bar:**
- Scenario-based stem, not abstract definition
- The asymmetry between CPU and memory is the actual learning point
- All distractors are things candidates plausibly say

---

### Sample 3 — tf-002 (state)

```json
{
  "id": "tf-002-mcq-1",
  "source_id": "tf-002",
  "domain": "terraform",
  "subdomain": "state",
  "priority": "critical",
  "difficulty": "medium",
  "question": "Two engineers run terraform apply simultaneously against the same S3 remote backend. State locking via DynamoDB is configured. What happens?",
  "options": {
    "correct": "The second apply fails immediately with a state lock error",
    "distractor_1": "Both applies succeed; Terraform merges the resulting state files",
    "distractor_2": "The second apply waits for the first to complete, then proceeds",
    "distractor_3": "Both applies succeed but the second silently overwrites the first's state"
  },
  "explanation": "DynamoDB state locking is advisory and fail-fast, not a queue. The second apply attempts to acquire the lock, sees it's held, and exits with an error. Distractor 1: Terraform never merges state files — that's a deliberate design choice. Distractor 2: it doesn't queue (some CI systems do, Terraform doesn't). Distractor 3 is literally what happens WITHOUT locking — the question is testing what locking actually prevents."
}
```

**Why this is the bar:**
- Distractor 3 is the safety-mechanism-absent answer — a strong trap
- Distractor 2 is a reasonable mental model that's just wrong
- Explanation contrasts each distractor with the correct behaviour

---

# Appendix B — Build sequencing recommendation

A suggested order of operations for Claude Code:

**Phase 1: Parse and plan (no MCQ writing yet)**
1. Fetch `Interview-Prep-Combined.md` from `https://raw.githubusercontent.com/engsnayl/interview-prep-app/main/Interview-Prep-Combined.md` (or clone the repo to `~/interview-prep-app/` if a local copy is preferred). Extract per-source metadata (id, domain, priority, the answer text).
2. Allocate each source to a "primary bank" (1, 2, or 3) per the distribution in section 3
3. Decide the 2 concept-angles per source that will become the 2 MCQs (lightweight outline — one sentence each)
4. **Surface this plan to Stephen for sign-off before authoring** — 1-2 hours of his time saved if any allocation looks wrong

**Phase 2: Pilot batch**
5. Author the first ~10 MCQs across 3-4 domains
6. Apply section 4.7 self-review
7. **Surface to Stephen for quality check** — does the bar match Appendix A?
8. Recalibrate if needed

**Phase 3: Full authoring**
9. Author the remaining ~200 MCQs in batches of 20-30
10. Self-review after each batch
11. Periodic surface to Stephen if anything feels off

**Phase 4: Runner build**
12. Build `runner.sh` + `lib/*.sh` scripts
13. Build `validate.sh`
14. Run validate.sh — fix any structural issues

**Phase 5: Smoke test and ship**
15. Run end-to-end smoke test (section 8.3) — Stephen does this
16. Commit + push to `cloud-engineer-labs` on a feature branch
17. PR for Stephen to review on GitHub web

---

**End of brief.**
