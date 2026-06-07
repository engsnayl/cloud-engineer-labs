#!/usr/bin/env python3
"""
Lab 093 — Linux Daily Drill
Boot-camp-mode CLI trainer for the Linux fundamentals a Cloud Engineer reaches
for daily. 50 scenarios across two tiers, parameterised so values change every
run. Tracks mastery: 3 clean runs in a row of a tier = mastered.

Usage:
    ./drill.py                       # default: random 30 from Tier 1
    ./drill.py --tier 1              # all 30 Tier 1 scenarios
    ./drill.py --tier 2              # all 20 Tier 2 scenarios
    ./drill.py --tier all            # all 50
    ./drill.py --count 10            # limit to N
    ./drill.py --category networking # filter by category
    ./drill.py --reveal              # cheat sheet, no drill
    ./drill.py --status              # show mastery progress
    ./drill.py --reset-mastery       # zero out mastery tracker
"""
import argparse
import json
import random
import re
import subprocess
import sys
import time
from pathlib import Path

try:
    import yaml
except ImportError:
    print("PyYAML not installed. Run: pip install pyyaml --break-system-packages")
    sys.exit(1)


# ─── Paths & files ────────────────────────────────────────────────────────────
SCRIPT_DIR    = Path(__file__).resolve().parent
SANDBOX       = SCRIPT_DIR / "sandbox"
SCENARIOS     = SCRIPT_DIR / "scenarios" / "drills.yaml"
BUILDER       = SCRIPT_DIR / "build-sandbox.sh"
MASTERY_FILE  = SCRIPT_DIR / ".mastery.json"


# ─── ANSI colours (no external deps) ─────────────────────────────────────────
class C:
    RESET  = "\033[0m"
    BOLD   = "\033[1m"
    DIM    = "\033[2m"
    RED    = "\033[31m"
    GREEN  = "\033[32m"
    YELLOW = "\033[33m"
    BLUE   = "\033[34m"
    MAGENTA = "\033[35m"
    CYAN   = "\033[36m"
    GREY   = "\033[90m"


def banner():
    print(f"""{C.CYAN}{C.BOLD}
╔══════════════════════════════════════════════════════════════╗
║              LAB 093 — LINUX DAILY DRILL                     ║
║         60 commands. Two tiers. Boot camp mode.              ║
╚══════════════════════════════════════════════════════════════╝{C.RESET}
""")


# ─── Parameterisation ─────────────────────────────────────────────────────────
# Scenarios may have a `params` block. Two flavours:
#   - flat dict: {VAR: [choice, choice, ...]} — each var picked independently
#   - paired:    {_PAIRED: [{VAR1: a, VAR2: b}, {VAR1: c, VAR2: d}]} — one whole
#                dict picked, used when vars must vary together coherently
# After picking, we substitute {VAR} placeholders into prompt, answer, and the
# string fields of `validate`. We also auto-derive {N_minus_one} and
# {N_minus_one_str} from any integer placeholder named N for regex use.

def materialise_scenario(scenario: dict) -> dict:
    """
    Pick concrete values for any params and substitute throughout the scenario.
    Returns a fully-materialised copy. Original is untouched.
    """
    s = json.loads(json.dumps(scenario))  # deep copy via JSON round-trip
    params = s.pop("params", None)
    if not params:
        return s

    chosen = {}
    if "_PAIRED" in params:
        chosen.update(random.choice(params["_PAIRED"]))
    else:
        for var, choices in params.items():
            chosen[var] = random.choice(choices)

    # Auto-derive helpers for integer params
    derived = {}
    for k, v in chosen.items():
        if isinstance(v, int):
            derived[f"{k}_minus_one"] = v - 1
    chosen.update(derived)

    # Substitute into prompt, answer, validate
    s["prompt"] = sub(s["prompt"], chosen)
    s["answer"] = sub(s["answer"], chosen)
    if isinstance(s["validate"], str):
        s["validate"] = sub(s["validate"], chosen)
    elif isinstance(s["validate"], list):
        s["validate"] = [sub(v, chosen) if isinstance(v, str) else v for v in s["validate"]]
    s["_chosen_params"] = chosen  # kept for debug, not displayed
    return s


def sub(text: str, params: dict) -> str:
    """
    Replace <<VAR>> with params[VAR] in text. The <<...>> syntax avoids any
    conflict with literal { and } characters that legitimately appear in shell
    commands (awk programs, jq filters, brace expansion etc.). Process longest
    keys first so <<N_minus_one>> isn't half-replaced by an <<N>> entry.
    """
    if not isinstance(text, str):
        return text
    for key in sorted(params.keys(), key=len, reverse=True):
        text = text.replace("<<" + key + ">>", str(params[key]))
    return text


# ─── Sandbox build ────────────────────────────────────────────────────────────
def build_sandbox():
    print(f"{C.DIM}Building sandbox...{C.RESET}")
    result = subprocess.run(
        ["bash", str(BUILDER), str(SANDBOX)],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"{C.RED}Sandbox build failed:{C.RESET}\n{result.stderr}")
        sys.exit(1)


# ─── Command execution ────────────────────────────────────────────────────────
def run_user_command(cmd: str, cwd: Path) -> tuple[int, str, str]:
    """
    Run user's command with a 5s timeout in the sandbox. Skip blocking ones.

    Uses Popen with start_new_session=True so we can kill the entire process
    group on timeout — otherwise pipelines like 'grep | other' can leave
    orphaned children holding file descriptors that corrupt the next input().
    """
    import os
    import signal

    blocking_prefixes = ("top", "htop", "vim", "vi ", "nano", "less", "more", "watch")
    cmd_stripped = cmd.strip()

    # Detect commands that open an interactive editor or block on the TTY.
    # These are validated by command pattern only — never actually executed —
    # because subprocess can't cleanly tear them down once they have control
    # of the terminal.
    interactive_patterns = [
        r"^tail\s+.*-.*f",          # tail -f
        r"^crontab\s+.*-e",          # crontab -e (any spacing)
        r"^visudo",                  # visudo
        r"^ssh\b",                   # ssh would actually try to connect
        r"^scp\b",                   # scp same
    ]

    if cmd_stripped.startswith(blocking_prefixes) or any(re.match(p, cmd_stripped) for p in interactive_patterns):
        return (0, "[interactive command — not executed in drill]", "")

    proc = None
    try:
        proc = subprocess.Popen(
            cmd, shell=True, cwd=cwd,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            stdin=subprocess.DEVNULL,        # never let the command read from our stdin
            text=True,
            start_new_session=True            # put it in its own process group
        )
        stdout, stderr = proc.communicate(timeout=5)
        return (proc.returncode, stdout, stderr)
    except subprocess.TimeoutExpired:
        # Kill the whole process group, not just the shell
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
        try:
            stdout, stderr = proc.communicate(timeout=1)
        except subprocess.TimeoutExpired:
            stdout, stderr = "", ""
        return (124, stdout, "[timed out after 5s]")
    except Exception as e:
        return (1, "", f"[error running command: {e}]")


# ─── Validation ───────────────────────────────────────────────────────────────
def validate(scenario: dict, cmd: str, stdout: str, stderr: str, cwd: Path,
             rc: int = 0) -> tuple[bool, str]:
    vt = scenario["validate_type"]
    expected = scenario["validate"]

    # Optional: require the command to have actually succeeded at runtime.
    # Used for scenarios where a syntactically-malformed command could still
    # match the regex (e.g. awk '(print $1)' contains "$1" but is wrong).
    # Set must_succeed: true on the scenario to enable.
    if scenario.get("must_succeed") and rc != 0:
        return (False, f"command exited with error (rc={rc}). Check syntax.")

    if vt == "command_pattern":
        if re.search(expected, cmd.strip()):
            return (True, "")
        return (False, "command shape doesn't match — check flags/syntax")

    if vt == "output_contains":
        missing = [s for s in expected if s not in stdout]
        if not missing:
            return (True, "")
        return (False, f"output missing expected content: {missing[0]!r}")

    if vt == "output_equals":
        if stdout.strip() == expected.strip():
            return (True, "")
        return (False, "output doesn't match exactly")

    if vt == "output_regex":
        if re.search(expected, stdout):
            return (True, "")
        return (False, "output doesn't match expected pattern")

    if vt == "side_effect":
        check = subprocess.run(expected, shell=True, cwd=cwd, capture_output=True)
        if check.returncode == 0:
            return (True, "")
        return (False, "the expected file/state wasn't produced")

    return (False, f"unknown validator type: {vt}")


# ─── Output rendering ─────────────────────────────────────────────────────────
def show_real_output(stdout: str, stderr: str):
    if not stdout.strip() and not stderr.strip():
        return
    print(f"{C.GREY}── output ──────────────────────────────────────{C.RESET}")
    out = stdout.rstrip("\n")
    if out:
        lines = out.split("\n")
        if len(lines) > 15:
            print("\n".join(lines[:15]))
            print(f"{C.DIM}... ({len(lines) - 15} more lines){C.RESET}")
        else:
            print(out)
    if stderr.strip():
        print(f"{C.RED}{stderr.rstrip()}{C.RESET}")
    print(f"{C.GREY}────────────────────────────────────────────────{C.RESET}")


# ─── One scenario ─────────────────────────────────────────────────────────────
def run_scenario(scenario: dict, idx: int, total: int, cwd: Path) -> dict:
    tier_label = f"{C.MAGENTA}T{scenario['tier']}{C.RESET}"
    print(f"\n{C.BOLD}{C.BLUE}━━━ Scenario {idx}/{total} ━━━{C.RESET} {tier_label} {C.DIM}({scenario['category']}){C.RESET}")
    print(f"{C.BOLD}{scenario['prompt']}{C.RESET}")

    attempts = 0
    started = time.time()

    while True:
        attempts += 1
        sys.stdout.flush()
        sys.stderr.flush()
        try:
            cmd = input(f"{C.CYAN}$ {C.RESET}").strip()
        except UnicodeDecodeError as e:
            # The input buffer contained bytes Python couldn't decode as UTF-8.
            # Most common cause: a stray non-ASCII byte from the SSH client or
            # keyboard layout (e.g. AltGr-space producing a non-breaking space).
            # Less common: locale not set to UTF-8 (check with `locale`).
            # Either way, don't crash — warn and re-prompt.
            print(f"\n{C.YELLOW}⚠ Input encoding glitch — couldn't decode that line.{C.RESET}")
            print(f"{C.DIM}  ({e}){C.RESET}")
            print(f"{C.DIM}  Usually a stray non-ASCII byte from the keyboard or SSH client.{C.RESET}")
            print(f"{C.DIM}  Just retype the command — the drill continues.{C.RESET}")
            attempts -= 1  # don't penalise the user for an internal hiccup
            continue
        except (EOFError, KeyboardInterrupt):
            print(f"\n{C.YELLOW}Drill aborted.{C.RESET}")
            sys.exit(0)

        if not cmd:
            continue
        if cmd in ("?", "help"):
            hint = scenario.get("hint")
            if hint:
                print(f"{C.YELLOW}Hint: {hint}{C.RESET}")
            else:
                print(f"{C.YELLOW}Hint: think about what tool produces the kind of output described.{C.RESET}")
            continue
        if cmd == "skip":
            print(f"{C.YELLOW}Answer: {C.BOLD}{scenario['answer']}{C.RESET}")
            print(f"{C.DIM}(skipped — counts as failed){C.RESET}")
            return {
                "id": scenario["id"], "tier": scenario["tier"],
                "category": scenario["category"],
                "passed": False, "attempts": attempts, "skipped": True,
                "elapsed": time.time() - started
            }
        if cmd in ("quit", "exit"):
            print(f"{C.YELLOW}Drill aborted.{C.RESET}")
            sys.exit(0)

        rc, stdout, stderr = run_user_command(cmd, cwd)
        passed, reason = validate(scenario, cmd, stdout, stderr, cwd, rc)

        if passed:
            show_real_output(stdout, stderr)
            # If the command's runtime failed but its shape was right (e.g. kill
            # on a fictional PID, systemctl status on a service not running),
            # be honest about what we verified.
            shape_only = (scenario["validate_type"] == "command_pattern"
                          and rc != 0
                          and not scenario.get("must_succeed"))
            if shape_only:
                print(f"{C.GREEN}✔ Command shape correct.{C.RESET} {C.DIM}(runtime failed in sandbox — that's expected here.) {scenario['teaches']}{C.RESET}")
            else:
                print(f"{C.GREEN}✔ Correct.{C.RESET} {C.DIM}{scenario['teaches']}{C.RESET}")
            return {
                "id": scenario["id"], "tier": scenario["tier"],
                "category": scenario["category"],
                "passed": True, "attempts": attempts, "skipped": False,
                "elapsed": time.time() - started
            }
        else:
            show_real_output(stdout, stderr)
            print(f"{C.RED}✘ Not quite — {reason}.{C.RESET} {C.DIM}(attempt {attempts}; 'skip' reveals, '?' for hint){C.RESET}")


# ─── Mastery tracking ─────────────────────────────────────────────────────────
# Goal: 3 consecutive clean runs of a tier = mastered. A "clean run" means every
# scenario in that tier was solved on the first attempt with no skips. Stored in
# .mastery.json so it persists. Use --status to see progress; --reset-mastery to clear.

def load_mastery() -> dict:
    """Load mastery state. Schema:
    {
      "tier_1":  {clean_streak, best_streak, total_runs, mastered},
      "tier_2":  {...},
      "categories": {
         "networking": {clean_streak, best_streak, total_runs, mastered},
         ...
      }
    }
    Older mastery files without 'categories' get auto-upgraded on read.
    """
    if MASTERY_FILE.exists():
        m = json.loads(MASTERY_FILE.read_text())
        # Auto-upgrade older files that don't have categories yet
        if "categories" not in m:
            m["categories"] = {}
        return m
    return {
        "tier_1": {"clean_streak": 0, "best_streak": 0, "total_runs": 0, "mastered": False},
        "tier_2": {"clean_streak": 0, "best_streak": 0, "total_runs": 0, "mastered": False},
        "categories": {}
    }


def save_mastery(m: dict):
    MASTERY_FILE.write_text(json.dumps(m, indent=2))


def update_mastery(results: list, tier_filter, category_filter=None, count_limited=False):
    """
    Update mastery state. Two paths:

    1. Full tier run (no --category, no --count): updates tier_1 or tier_2 mastery.
    2. Full category run (--category X, no --count, no --tier OR --tier all):
       updates that category's mastery. Categories with <2 scenarios are skipped
       — a single-scenario "clean run streak" devalues the flag.

    Anything else (--count, mixed scope) returns None — no mastery update.
    Returns the updated mastery dict for the relevant scope (for display), or None.
    """
    if count_limited:
        return None  # cherry-picking is not mastery

    # Path 1: full single-tier run
    if category_filter is None and tier_filter in ("1", "2"):
        tier_results = [r for r in results if str(r["tier"]) == tier_filter]
        if not tier_results:
            return None
        clean = all(r["passed"] and r["attempts"] == 1 and not r["skipped"] for r in tier_results)
        m = load_mastery()
        key = f"tier_{tier_filter}"
        m[key]["total_runs"] += 1
        if clean:
            m[key]["clean_streak"] += 1
            m[key]["best_streak"] = max(m[key]["best_streak"], m[key]["clean_streak"])
            if m[key]["clean_streak"] >= 3:
                m[key]["mastered"] = True
        else:
            m[key]["clean_streak"] = 0
        save_mastery(m)
        return {"scope": "tier", "name": key, "data": m[key]}

    # Path 2: full category run (any tier — including 'all')
    if category_filter is not None:
        # Only categories with >=2 scenarios qualify for mastery
        if len(results) < 2:
            return None
        clean = all(r["passed"] and r["attempts"] == 1 and not r["skipped"] for r in results)
        m = load_mastery()
        cats = m.setdefault("categories", {})
        cat = cats.setdefault(category_filter, {
            "clean_streak": 0, "best_streak": 0, "total_runs": 0, "mastered": False
        })
        cat["total_runs"] += 1
        if clean:
            cat["clean_streak"] += 1
            cat["best_streak"] = max(cat["best_streak"], cat["clean_streak"])
            if cat["clean_streak"] >= 3:
                cat["mastered"] = True
        else:
            cat["clean_streak"] = 0
        save_mastery(m)
        return {"scope": "category", "name": category_filter, "data": cat}

    return None


# ─── End-of-drill report ──────────────────────────────────────────────────────
def print_results(results: list, total_elapsed: float, mastery_update):
    print(f"\n\n{C.BOLD}{C.CYAN}═══ DRILL COMPLETE ═══{C.RESET}\n")
    passed_first_try = sum(1 for r in results if r["passed"] and r["attempts"] == 1)
    passed_eventually = sum(1 for r in results if r["passed"])
    skipped = sum(1 for r in results if r["skipped"])
    total = len(results)

    print(f"  {C.GREEN}First-try clean:{C.RESET}    {passed_first_try}/{total}")
    print(f"  {C.YELLOW}Solved (any attempts):{C.RESET}  {passed_eventually}/{total}")
    print(f"  {C.RED}Skipped:{C.RESET}             {skipped}/{total}")
    print(f"  {C.DIM}Total time:{C.RESET}          {int(total_elapsed // 60)}m {int(total_elapsed % 60)}s")

    cats = {}
    for r in results:
        cats.setdefault(r["category"], []).append(r)
    print(f"\n  {C.BOLD}By category:{C.RESET}")
    for cat in sorted(cats):
        rs = cats[cat]
        clean = sum(1 for r in rs if r["passed"] and r["attempts"] == 1)
        col = C.GREEN if clean == len(rs) else C.YELLOW if clean >= len(rs) * 0.6 else C.RED
        print(f"    {col}{cat:20s}{C.RESET} {clean}/{len(rs)} clean")

    rough = [r for r in results if not r["passed"] or r["attempts"] > 1]
    if rough:
        print(f"\n  {C.BOLD}Drill these again tomorrow:{C.RESET}")
        for r in rough:
            tag = "skipped" if r["skipped"] else f"{r['attempts']} attempts"
            print(f"    • Scenario {r['id']:>2} (T{r['tier']}/{r['category']}) — {tag}")
    else:
        print(f"\n  {C.GREEN}{C.BOLD}Clean run.{C.RESET}")

    if mastery_update:
        data = mastery_update["data"]
        scope = mastery_update["scope"]
        name = mastery_update["name"]
        label = (
            f"Tier {name[-1]}" if scope == "tier"
            else f"Category '{name}'"
        )
        print(f"\n  {C.BOLD}Mastery ({label}):{C.RESET}")
        if data["mastered"]:
            print(f"    {C.GREEN}{C.BOLD}✓ MASTERED{C.RESET} {C.DIM}(after {data['best_streak']} clean runs in a row){C.RESET}")
            if scope == "tier":
                print(f"    {C.DIM}You can stop drilling this tier. Move on.{C.RESET}")
            else:
                print(f"    {C.DIM}This category is solid. Time for a different one or a full-tier run.{C.RESET}")
        else:
            streak = data["clean_streak"]
            print(f"    Clean streak: {C.CYAN}{streak}/3{C.RESET}  {C.DIM}(best ever: {data['best_streak']}){C.RESET}")
            if streak == 0:
                print(f"    {C.DIM}Streak reset. Need 3 clean runs in a row to master.{C.RESET}")
            elif streak < 3:
                print(f"    {C.DIM}{3 - streak} more clean run(s) to master.{C.RESET}")
    print()


def show_status():
    m = load_mastery()
    print(f"\n{C.BOLD}Mastery progress{C.RESET}\n")

    print(f"  {C.BOLD}Tiers:{C.RESET}")
    for tier in ("tier_1", "tier_2"):
        d = m[tier]
        label = "Tier 1 (fundamentals)" if tier == "tier_1" else "Tier 2 (interview-edge)"
        if d["mastered"]:
            mark = f"{C.GREEN}✓ MASTERED{C.RESET}"
        else:
            mark = f"streak {C.CYAN}{d['clean_streak']}/3{C.RESET}"
        print(f"    {label:30s}  {mark}")
        print(f"      {C.DIM}total runs: {d['total_runs']}, best streak: {d['best_streak']}{C.RESET}")

    cats = m.get("categories", {})
    if cats:
        print(f"\n  {C.BOLD}Categories:{C.RESET}")
        # Sort: mastered first, then by streak desc, then alphabetically
        sorted_cats = sorted(cats.items(), key=lambda kv: (
            not kv[1]["mastered"], -kv[1]["clean_streak"], kv[0]
        ))
        for name, d in sorted_cats:
            if d["mastered"]:
                mark = f"{C.GREEN}✓ MASTERED{C.RESET}"
            else:
                mark = f"streak {C.CYAN}{d['clean_streak']}/3{C.RESET}"
            print(f"    {name:30s}  {mark}  {C.DIM}(runs: {d['total_runs']}, best: {d['best_streak']}){C.RESET}")
    else:
        print(f"\n  {C.DIM}No category drills run yet. Try: start linux drill --category <name>{C.RESET}")

    print()
    if m["tier_1"]["mastered"] and m["tier_2"]["mastered"]:
        print(f"  {C.GREEN}{C.BOLD}Both tiers mastered. Linux fundamentals confirmed.{C.RESET}")
        print(f"  {C.DIM}Stop drilling. Go interview.{C.RESET}\n")


# ─── Main ─────────────────────────────────────────────────────────────────────
def main():
    ap = argparse.ArgumentParser(description="Linux Daily Drill")
    ap.add_argument("--tier", default="1", choices=["1", "2", "all"], help="Tier to drill (default: 1, or 'all' when --category is used without --tier)")
    ap.add_argument("--count", type=int, default=None, help="Limit to N scenarios")
    ap.add_argument("--category", type=str, default=None, help="Filter to one category")
    ap.add_argument("--reveal", action="store_true", help="Print all answers and exit")
    ap.add_argument("--status", action="store_true", help="Show mastery progress and exit")
    ap.add_argument("--reset-mastery", action="store_true", help="Zero out mastery tracker")
    ap.add_argument("--no-shuffle", action="store_true", help=argparse.SUPPRESS)  # debug
    args = ap.parse_args()

    # Detect whether --tier was explicitly provided (vs left at default).
    # Used so that --category alone defaults to all-tier scope, not tier 1.
    args.tier_explicit = any(a == "--tier" or a.startswith("--tier=") for a in sys.argv[1:])

    if args.reset_mastery:
        if MASTERY_FILE.exists():
            MASTERY_FILE.unlink()
        print(f"{C.YELLOW}Mastery tracker reset.{C.RESET}")
        return

    if args.status:
        show_status()
        return

    data = yaml.safe_load(SCENARIOS.read_text())
    all_scenarios = data["scenarios"]

    if args.reveal:
        print(f"{C.BOLD}Cheat sheet — all {len(all_scenarios)} scenarios (canonical answers, before parameterisation):{C.RESET}\n")
        for tier in (1, 2):
            tier_scenarios = [s for s in all_scenarios if s["tier"] == tier]
            print(f"{C.MAGENTA}{C.BOLD}── TIER {tier} ──{C.RESET}")
            for s in tier_scenarios:
                print(f"  {C.CYAN}{s['id']:>2}{C.RESET} ({s['category']}) {s['prompt']}")
                print(f"      {C.GREEN}→ {s['answer']}{C.RESET}\n")
        return

    # Filter by tier. If --category was specified but --tier wasn't explicitly
    # given, default to "all" — users running a category drill expect ALL
    # scenarios in that category across both tiers, not just Tier 1.
    if args.category and not args.tier_explicit:
        scenarios = list(all_scenarios)
    elif args.tier == "1":
        scenarios = [s for s in all_scenarios if s["tier"] == 1]
    elif args.tier == "2":
        scenarios = [s for s in all_scenarios if s["tier"] == 2]
    else:
        scenarios = list(all_scenarios)

    # Filter by category
    if args.category:
        scenarios = [s for s in scenarios if s["category"] == args.category]
        if not scenarios:
            cats = sorted({s["category"] for s in all_scenarios})
            print(f"{C.RED}No scenarios in that category.{C.RESET} Available: {', '.join(cats)}")
            sys.exit(1)

    # Materialise (substitute params) BEFORE shuffle so randomness covers params too
    scenarios = [materialise_scenario(s) for s in scenarios]

    if not args.no_shuffle:
        random.shuffle(scenarios)
    if args.count:
        scenarios = scenarios[:args.count]

    banner()
    build_sandbox()
    print(f"{C.DIM}Sandbox: {SANDBOX}{C.RESET}")

    # Describe what was actually selected so the user can see the filter at a glance
    if args.category and not args.tier_explicit:
        scope_label = f"all (filtered by category: {args.category})"
    elif args.category:
        scope_label = f"{args.tier} (filtered by category: {args.category})"
    else:
        scope_label = args.tier
    print(f"{C.DIM}Tier: {scope_label}  •  Scenarios: {len(scenarios)}{C.RESET}")
    print(f"{C.DIM}Type your command at the $ prompt. 'skip' to reveal, 'quit' to abort.{C.RESET}\n")

    results = []
    started = time.time()
    for i, s in enumerate(scenarios, start=1):
        results.append(run_scenario(s, i, len(scenarios), SANDBOX))

    # Mastery updates if user ran a full single-tier OR full single-category drill.
    # Not eligible: --count limit, or mixed/all tiers without a category filter.
    mastery_update = update_mastery(
        results,
        tier_filter=args.tier,
        category_filter=args.category,
        count_limited=(args.count is not None)
    )

    print_results(results, time.time() - started, mastery_update)


if __name__ == "__main__":
    main()
