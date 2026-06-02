# Control sample — 6 unflagged MCQs

**Purpose:** Confirm the 82 "unflagged" MCQs are actually at the pilot bar before committing to rewriting the flagged 126. If the unflagged work is weaker than the audit thinks, expand audit scope before Tier 1.

**Seed:** SAMPLE_SEED=4096 (default) — re-runnable with the same seed.

**Distribution of sample:** 6 domains hit (AWS, K8s, CI/CD, Terraform, Docker, Git). Linux not sampled this round; if you want one, re-seed.

---

## Method

Each MCQ assessed against the **operationalised 6-month-candidate test**:

> "Could a real candidate with ~6 months of cloud experience but no deep knowledge of this specific feature actually believe this distractor? If answering requires inventing a feature, version, billing detail, or limit that doesn't exist, replace it."

Plus: scenario-stem check, explanation-covers-distractors check, single-source-pair check (other MCQ from same source_id tests a distinct facet).

---

## Per-MCQ assessment

### 1. git-006-mcq-1 — git — bank 2

**Stem:** "You add `secrets.json` to `.gitignore` AFTER having already committed and pushed the file. What happens?"

**Stem type:** scenario ✓

**Correct:** ".gitignore only affects untracked files; secrets.json is already tracked, so it stays in the repo and continues to be committed on changes" — correct.

**Distractors:**
- **distractor_1** "Git automatically retroactively removes the file from history once it's added to .gitignore" — **PASS.** Classic 6-month misconception (people genuinely believe gitignore is retroactive).
- **distractor_2** "The next push fails because Git refuses to push a file that's now in .gitignore until you delete it from disk" — **MILD FABRICATION.** Git does not have a push-time enforcement on gitignored-but-tracked files. The author invented this failure mode. Candidate might believe Git has stricter enforcement than it does, so the candidate-believability check is marginal — but the underlying mechanism is invented.
- **distractor_3** "Future commits will exclude the file silently; the historical commits remain but new versions stop being tracked" — **PASS.** Common candidate model ("gitignore = stop tracking from here").

**Explanation:** Addresses each distractor; ends with the real-world hook ("#1 gotcha behind 'I gitignored the file...'"). ✓

**Verdict:** **borderline** — distractor_2 is a mild fabrication that should have been caught. Otherwise at bar.

---

### 2. tf-011-mcq-1 — terraform — bank 1

**Stem:** "You manage 5 AWS IAM users with `resource ... { count = length(var.usernames) ... }`... You remove the username at index 2 from the list and run terraform apply. What happens?"

**Stem type:** scenario ✓

**Correct:** "Terraform recreates the IAM users at indices 2, 3, and 4 because count addresses by position..." — correct, and the explanation is excellent.

**Distractors:**
- **distractor_1** "Terraform destroys only the IAM user at index 2 and leaves the remaining users untouched" — **PASS.** Classic count-vs-for_each confusion.
- **distractor_2** "Terraform refuses to apply because count cannot shrink after the first apply without a terraform state mv first" — **MILD FABRICATION.** The "count cannot shrink without state mv" rule does not exist. Author invented a constraint. Candidate-believability is OK (a candidate worried about state management might believe this), but the specific mechanism is invented.
- **distractor_3** "Terraform destroys the IAM user at index 4 since count drops from 5 to 4, treating the change as a tail removal" — **PASS.** Plausible candidate model (most languages shrink lists at the tail).

**Explanation:** Strong; offers the for_each fix and notes IAM-specific destructiveness. ✓

**Verdict:** **borderline** — distractor_2 invents a Terraform constraint.

---

### 3. cicd-012-mcq-2 — cicd — bank 3

**Stem:** "Your matrix has `os: [ubuntu, macos, windows]` and `node: [18, 20]` but you don't want the macos+node18 combination because it's flaky. How do you skip it?"

**Stem type:** scenario ✓

**Correct:** "Use `exclude:` in the strategy..." — correct.

**Distractors:**
- **distractor_1** `continue-on-error: true` — **PASS.** Real GHA feature in wrong context.
- **distractor_2** `if: ${{ !(matrix.os == 'macos' && matrix.node == 18) }}` — **PASS.** Real feature, would technically work but as a hack. Half-correct approach.
- **distractor_3** `skip-matrix:` YAML key — **FABRICATION.** No such GitHub Actions key exists. The author invented a YAML key. A 6-month candidate might believe it exists because GHA has many keys, but the specific name was invented. **Fails the operationalised test.**

**Explanation:** Calls out distractor_3 as "invents a `skip-matrix:` key that doesn't exist" — so the explanation actually documents the fabrication. ✓ on explanation, ✗ on distractor design.

**Verdict:** **fails-rubric** — distractor_3 fabricates a YAML key. The fact that the explanation has to call it "doesn't exist" is the tell.

---

### 4. docker-010-mcq-2 — docker — bank 2

**Stem:** "A container starts and exits immediately. `docker logs` shows nothing. What's the next diagnostic step?"

**Stem type:** scenario ✓

**Correct:** "Run `docker inspect <container>` and look at State (exit code, error) plus run with `-it --entrypoint=sh`..." — correct, practical.

**Distractors:**
- **distractor_1** "Run `docker exec -it <container> sh` to drop into the exited container..." — **PASS.** Classic candidate misconception (exec requires running container).
- **distractor_2** "Increase the container's stop timeout to 60 seconds, which gives docker logs more time to capture output before exit" — **MILD FABRICATION.** Stop timeout governs graceful-shutdown waits, not log capture. The causal link between stop timeout and log capture is invented. Candidate might believe it via vague mental model of "longer timeout = more time for things," but the specific claim is invented.
- **distractor_3** "Restart Docker daemon to flush log buffers; transient containers often lose stdout to a kernel buffer that the daemon doesn't drain" — **SEVERE FABRICATION.** There is no "kernel buffer the daemon doesn't drain" mechanism. The Docker daemon captures stdout/stderr at process runtime via the configured logging driver; transient containers don't have output drop into an unflushed kernel buffer. The author invented an authoritative-sounding mechanism. **Worst kind of fabrication** — high specificity, plausible jargon, completely invented. **Fails the operationalised test on multiple levels.**

**Explanation:** Calls distractor_3 a "fabricated daemon-restart fix" but doesn't address the kernel-buffer claim. ✗ on distractor design and partial-✗ on explanation.

**Verdict:** **fails-rubric** — distractor_3 is exactly the pattern the audit was designed to catch (authoritative-sounding invented mechanism). The fact that it slipped past `audit_suspect.py` is significant: the heuristic doesn't catch fabricated mechanisms phrased without version numbers or specific feature names.

---

### 5. k8s-002-mcq-2 — kubernetes — bank 2

**Stem:** "A pod is in `CrashLoopBackOff`. What does this state tell you?"

**Stem type:** **borderline scenario.** The "A pod is in X" framing is scenario-shaped, but the question itself ("what does this state tell you") is recall. The audit script's stem classifier called this scenario because "A pod" matches a scenario marker; on stricter reading it's pseudo-scenario.

**Correct:** "The container has crashed multiple times in quick succession and the kubelet is now restarting it with exponential backoff..." — correct.

**Distractors:**
- **distractor_1** "ImagePullBackOff..." — **PASS.** Classic 6-month confusion between BackOff states.
- **distractor_2** "Eviction churn..." — **PASS.** Plausible misattribution.
- **distractor_3** "Readiness flap..." — **PASS.** Plausible misattribution that gets the cycle-state wrong.

**Explanation:** Excellent — contrasts each state with the correct one specifically.

**Verdict:** **at-bar** (with a stem caveat) — the pseudo-scenario stem is mild; the distractors are all real candidate confusions and excellent. If we're rebuilding stems for the flagged set, this one would still pass.

---

### 6. aws-020-mcq-2 — aws — bank 3

**Stem:** "During a deploy, an ASG with a target tracking policy starts terminating instances that the deployment script just registered. What feature should the deployment use to prevent this?"

**Stem type:** scenario ✓ (concrete deploy + observed behaviour + design question)

**Correct:** "Instance scale-in protection on the new instances, or the broader ASG-level scale-in protection setting..." — correct.

**Distractors:**
- **distractor_1** "Deployment cooldown on the ASG — extending the cooldown to several minutes blocks all scale-in actions during a deploy" — **PASS.** Classic cooldown-vs-protection confusion.
- **distractor_2** "Health check grace period..." — **PASS.** Real feature, wrong context.
- **distractor_3** "Termination policy 'OldestInstance'..." — **PASS.** Plausible candidate model that almost works.

**Explanation:** Solid; explains why each distractor doesn't actually solve the problem.

**Verdict:** **at-bar** — clean across the board.

---

## Aggregate

| Verdict | Count | MCQs |
|---|---|---|
| at-bar | 2 | k8s-002-mcq-2, aws-020-mcq-2 |
| borderline | 2 | git-006-mcq-1 (mild fab in d2), tf-011-mcq-1 (mild fab in d2) |
| fails-rubric | 2 | cicd-012-mcq-2 (`skip-matrix:` key invented), docker-010-mcq-2 (kernel-buffer mechanism invented) |

**Strict count of "at-bar": 2 / 6.**
**Inclusive of borderline: 4 / 6.**

---

## Per-plan threshold

- 6/6 at-bar → confirm 82 off the table, proceed to Tier 1
- 4-5/6 at-bar → proceed but expand spot-check during final re-audit
- <4/6 at-bar → STOP. Expand audit scope.

The strict count (2/6) trips the STOP threshold. The inclusive count (4/6) sits at the lower edge of the "proceed with expanded spot-check" band. Where we land depends on whether borderline = at-bar for your standards.

---

## What this tells us about the 82 "unflagged"

The audit's `audit_suspect.py` heuristic catches version-deprecation claims, specific durations/percents, "automatic/implicit/built-in" prose, and specific flags. It **does not** catch:

- **Invented mechanisms** phrased as plain English (the docker kernel-buffer case)
- **Invented YAML keys / config fields** that read as normal config (`skip-matrix:`)
- **Invented constraints** phrased as Terraform/Git rules (the tf "count cannot shrink without state mv" case, the git "push refuses" case)

Extrapolating naively: if 2/6 unflagged have clear fabrications and 2/6 have mild ones, the 82 unflagged set may contain **~8 to ~27** further fabrications the audit didn't catch.

---

## Recommendation: EXPAND AUDIT SCOPE

Specifically: re-run `audit_suspect.py` after expanding its pattern set to include:

1. **Mechanism-claim patterns:** phrases like "buffer", "drain", "queue", "kernel-level", "daemon-level" combined with cause-effect connectors ("causes", "because", "results in") — these flag authoritative-sounding mechanism inventions.
2. **Invented-key patterns:** YAML/HCL keys that don't appear in the relevant official docs corpus (this is harder — needs a small allowlist or an LLM-pass).
3. **Invented-constraint patterns:** "cannot X without Y first" / "refuses to X if Y" — flag for manual review.

OR, more practically: do an LLM-based pass over the 82 unflagged MCQs specifically looking for the pattern types above. The audit script gets you 80% of the way; an LLM spot-check covers the remaining classes.

After expansion, re-baseline `phase3-audit/flagged-mcqs.json` and re-run this control check with a different seed. Only proceed to Tier 1 once the 82 unflagged are robustly verified.

---

## Session context status

- Estimated context usage: **~55–60%** — comfortable, no handoff needed yet
- Handoff recommended: no
- Notes: Plan write + Tasks 0/1/2 done in this session. Tier 1 will start in a fresh session per the audit README's original recommendation.

---

## Decision requested

1. **Proceed / expand-scope / different action?**
   - Recommended: expand-scope, given 2 clear fabrications in 6 random unflagged MCQs.
2. **Should I treat the borderline cases as fabrications too?** Your call on how strict "operationalised" is.
3. **Audit scope expansion approach:** add patterns to `audit_suspect.py`, do an LLM-based pass, or both?
4. **What to do with the 2 fails-rubric MCQs surfaced here** (cicd-012-mcq-2, docker-010-mcq-2)? Add them to the Tier 2 batch (distractor swaps) immediately, or hold for the broader expanded-scope re-audit?
