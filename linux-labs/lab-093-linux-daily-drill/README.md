# Lab 093 — Linux Daily Drill

A boot-camp-mode CLI trainer for the Linux fundamentals a Cloud Engineer reaches for daily. **50 scenarios across two tiers**, with values that change every run so you can't memorise your way out. The goal is **mastery, not daily routine** — drill until both tiers are confirmed mastered, then walk away.

This is not a normal investigative cold-ticket lab. It is a **drill harness** — training equipment, not portfolio evidence. There is deliberately no `CHALLENGE.md`, no `validate.sh`, no PPT, no YouTube walkthrough. The "solution" is the mastery flag in `.mastery.json` and the fluency it represents.

---

## What it does

- 50 scenarios: **30 Tier 1 fundamentals + 20 Tier 2 interview-edge**
- **Parameterised** — file sizes, line counts, search terms, service names, port numbers all randomise each run. The prompt is different every time.
- **Boot camp mode** — scenarios loop until you solve them
- **Flexible validation** — any command producing the right output passes (some are validated by command shape when running them isn't safe in a sandbox)
- **Mastery tracking** — 3 consecutive clean runs of a tier (every scenario solved first-try, no skips) marks it MASTERED. When both tiers are mastered, you're done.
- Real command output shown each time so you also build pattern recognition

---

## Setup

```bash
cd ~/cloud-engineer-labs/cloud-labs/lab-093-linux-daily-drill
pip install pyyaml --break-system-packages   # one-time
sudo apt install jq                          # for Tier 2 jq scenarios
chmod +x drill.py build-sandbox.sh
```

## Run it

```bash
./drill.py                       # default: all 30 Tier 1 scenarios
./drill.py --tier 2              # all 20 Tier 2 scenarios
./drill.py --tier all            # all 50 mixed
./drill.py --count 10            # quick subset (won't count toward mastery)
./drill.py --category networking # focused practice on one weak area
./drill.py --status              # see mastery progress
./drill.py --reveal              # cheat sheet (templates, before parameterisation)
./drill.py --reset-mastery       # zero out mastery tracker
```

In-drill commands at the `$` prompt:

| Type      | Effect                                       |
|-----------|----------------------------------------------|
| `?`       | Show a vague hint                            |
| `skip`    | Reveal answer, move on (counts as failed)    |
| `quit`    | Abort the drill                              |

**Mastery only updates when you run a full single-tier drill** (no `--count`, no `--category`). This prevents gaming it with 1-scenario clean runs.

---

## Coverage

### Tier 1 — 30 fundamentals
| Category         | Count | Examples                                  |
|------------------|-------|-------------------------------------------|
| file-ops         | 6     | `ls -la`, `head`, `tail -f`, `cp`, `touch` |
| text-processing  | 6     | `grep -i/-c/-v`, `awk`, `sed`, `sort \| uniq` |
| processes        | 4     | `ps aux`, `pgrep`, `top`, `kill -9`       |
| search           | 3     | `find -name`, `find -size`, `find -mtime` |
| disk-memory      | 3     | `df -h`, `du -sh`, `free -h`              |
| networking       | 3     | `ss -tlnp`, `ip a`, `curl -I`             |
| permissions      | 2     | `chmod +x`, `chown`                       |
| archives         | 2     | `tar -czf`, `tar -xzf`                    |
| systemd          | 1     | `systemctl status`                        |

### Tier 2 — 20 interview-edge
| Category         | Count | Examples                                            |
|------------------|-------|-----------------------------------------------------|
| pipelines        | 4     | `find \| xargs rm`, top-N pipeline, `watch`, `tee` |
| text-processing  | 3     | `cut -d`, `tr`, `wc`                                |
| json             | 2     | `jq '.field'`, `jq -r '.array[].field'`             |
| processes        | 2     | `lsof -c`, `lsof -i :PORT`                          |
| networking       | 2     | `dig`, `nc -zv`                                     |
| sync             | 1     | `rsync -av`                                         |
| systemd          | 1     | `journalctl -u UNIT -n N`                           |
| env              | 2     | `echo $VAR` / `printenv`, `export`                  |
| shell-control    | 3     | `&&`, `$?`, `which`/`type`                          |

Use `./drill.py --reveal` for the full list with canonical answers.

---

## How parameterisation works

Many scenarios have a `params` block in `scenarios/drills.yaml`. Each run, the runner picks one value (or one paired set) and substitutes it into the prompt, the answer, and the validator. Example:

```yaml
- id: 02
  prompt: "Show the first <<N>> lines of the file 'access.log'."
  answer: "head -n <<N>> access.log"
  params:
    N: [3, 5, 7, 10]
```

So one run asks "Show the first 3 lines", another asks "Show the first 7 lines". You can't muscle-memory `head -n 5` and skate through — you have to read the prompt every time.

Where multiple values must vary together coherently, scenarios use `_PAIRED`:

```yaml
- id: 14
  params:
    _PAIRED:
      - { OLD: "localhost", NEW: "127.0.0.1" }
      - { OLD: "5432",      NEW: "5433" }
```

---

## How validation works

Three modes, picked per scenario:

- **`output_contains`** — runs your command, checks stdout contains expected fingerprint(s). Most flexible.
- **`command_pattern`** — regex against the typed command. Used for syntax-critical commands (`tail -f`, `ss -tlnp`) where running them isn't safe or possible in a sandbox.
- **`side_effect`** — runs your command, then checks the resulting filesystem state. Used for `touch`, `cp`, `chmod`, `tar -czf`.

Interactive commands (`top`, `htop`, `tail -f`, `vim`, `watch`) are detected by prefix and **not actually executed** — they're validated by command pattern only.

---

## Mastery

- A **clean run** = every scenario in the tier solved on first attempt, no skips, no retries.
- 3 consecutive clean runs of a tier = **MASTERED**.
- Streak resets to 0 on any non-clean run. `best_streak` is preserved as a high-water mark.
- Both tiers MASTERED = you're done. The drill stops being useful for you. Stop drilling and go interview.

Check progress any time with `./drill.py --status`.

---

## Sandbox

`build-sandbox.sh` rebuilds a fresh `./sandbox/` at the start of every run with `access.log`, `app.log`, `config.txt`, `hosts.txt`, `big.dat`, `deploy.sh`, `sample.tar.gz`, `data.json`, and `src/`. Your real home directory is never touched. Commands run with `cwd=sandbox` and a 5-second timeout.

---

## Extending

Add new scenarios to `scenarios/drills.yaml`. Schema:

```yaml
- id: 51
  tier: 1               # or 2
  category: networking
  prompt: "Plain-English description with <<PARAM>> if you want it."
  validate_type: output_contains   # or command_pattern, side_effect, output_regex, output_equals
  validate: ["expected substring"] # type-dependent
  answer: "the canonical command with <<PARAM>>"
  teaches: "One-line takeaway."
  params:               # optional
    PARAM: [a, b, c]
```

If your scenario references a new file, add its creation to `build-sandbox.sh`.

**Placeholder syntax is `<<NAME>>` not `{NAME}`** — this avoids collisions with literal `{` and `}` in `awk` programs, `jq` filters, and brace expansion.
