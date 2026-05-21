#!/usr/bin/env bash
# gitdrill - git practice drill runner
#
# Mirrors the cloud-engineer-labs `lab` function pattern.
# Each drill seeds a fresh repo in /tmp/gitdrill-NNN/ and validates against real git state.
#
# Usage:
#   gitdrill list                  # show all available drills
#   gitdrill start NNN             # seed and start drill NNN
#   gitdrill validate              # validate current drill (must be cd'd into it)
#   gitdrill reset                 # re-seed the current drill from scratch
#   gitdrill show NNN              # print solution (only after solving, or with --force)
#   gitdrill where                 # print path to current drill's working dir
#   gitdrill help                  # show this

set -uo pipefail

# Resolve drill root: assume this script lives in git-drills/tools/
GITDRILL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRILLS_DIR="${GITDRILL_ROOT}/drills"
WORK_ROOT="/tmp"
STATE_FILE="${HOME}/.gitdrill-state"

# Colors
if [[ -t 1 ]]; then
    C_RED=$'\033[0;31m'
    C_GREEN=$'\033[0;32m'
    C_YELLOW=$'\033[0;33m'
    C_BLUE=$'\033[0;34m'
    C_BOLD=$'\033[1m'
    C_RESET=$'\033[0m'
else
    C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_BOLD='' C_RESET=''
fi

_gd_die()   { printf '%sERROR:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
_gd_warn()  { printf '%s%s%s\n' "$C_YELLOW" "$*" "$C_RESET" >&2; }
_gd_info()  { printf '%s%s%s\n' "$C_BLUE" "$*" "$C_RESET"; }
_gd_ok()    { printf '%s✓ %s%s\n' "$C_GREEN" "$*" "$C_RESET"; }
_gd_fail()  { printf '%s✗ %s%s\n' "$C_RED" "$*" "$C_RESET"; }

# Find a drill directory by number (zero-padded or not)
_gd_find_drill() {
    local num="$1"
    # Normalise: strip leading zeros, then re-pad to 3 digits
    local padded
    padded=$(printf '%03d' "$((10#$num))" 2>/dev/null) || _gd_die "Invalid drill number: $num"
    local match
    match=$(find "$DRILLS_DIR" -maxdepth 1 -type d -name "${padded}-*" 2>/dev/null | head -n 1)
    [[ -n "$match" ]] || _gd_die "No drill found for number $padded"
    echo "$match"
}

_gd_work_dir() {
    local drill_dir="$1"
    local drill_name
    drill_name=$(basename "$drill_dir")
    echo "${WORK_ROOT}/gitdrill-${drill_name}"
}

_gd_save_state() {
    echo "$1" > "$STATE_FILE"
}

_gd_load_state() {
    [[ -f "$STATE_FILE" ]] && cat "$STATE_FILE" || echo ""
}

# Find the drill the user is currently in by looking at $PWD
_gd_current_drill() {
    local pwd_real
    pwd_real=$(pwd -P)
    # If we're inside a gitdrill working dir, derive the drill
    if [[ "$pwd_real" == "${WORK_ROOT}/gitdrill-"* ]]; then
        local drill_name="${pwd_real#${WORK_ROOT}/gitdrill-}"
        # Trim anything after the drill dir (e.g. subdirs inside the repo)
        drill_name="${drill_name%%/*}"
        echo "${DRILLS_DIR}/${drill_name}"
    else
        # Fall back to saved state
        local saved
        saved=$(_gd_load_state)
        [[ -n "$saved" ]] && echo "$saved" || echo ""
    fi
}

cmd_list() {
    printf '%sAvailable drills:%s\n\n' "$C_BOLD" "$C_RESET"
    local d
    for d in "$DRILLS_DIR"/*/; do
        [[ -d "$d" ]] || continue
        local name
        name=$(basename "$d")
        local title=""
        if [[ -f "${d}CHALLENGE.md" ]]; then
            # First # heading in CHALLENGE.md
            title=$(grep -m 1 '^# ' "${d}CHALLENGE.md" | sed 's/^# //')
        fi
        printf '  %s%s%s  %s\n' "$C_BLUE" "$name" "$C_RESET" "$title"
    done
}

cmd_start() {
    local num="${1:-}"
    [[ -n "$num" ]] || _gd_die "Usage: gitdrill start NNN"
    local drill_dir
    drill_dir=$(_gd_find_drill "$num")
    local work_dir
    work_dir=$(_gd_work_dir "$drill_dir")
    local seed="${drill_dir}/seed.sh"
    local challenge="${drill_dir}/CHALLENGE.md"

    [[ -f "$seed" ]] || _gd_die "Missing seed.sh in $drill_dir"
    [[ -f "$challenge" ]] || _gd_die "Missing CHALLENGE.md in $drill_dir"

    # Nuke any prior working dir for this drill
    if [[ -d "$work_dir" ]]; then
        _gd_warn "Removing existing working dir: $work_dir"
        rm -rf "$work_dir"
    fi

    mkdir -p "$work_dir"
    _gd_info "Seeding drill in $work_dir ..."
    (
        cd "$work_dir" || exit 1
        # Run seed in a subshell so it can't break our env
        bash "$seed"
    ) || _gd_die "Seed script failed"

    _gd_save_state "$drill_dir"

    printf '\n%s%s%s\n' "$C_BOLD" "════════════════════════════════════════════════════════════" "$C_RESET"
    cat "$challenge"
    printf '\n%s%s%s\n' "$C_BOLD" "════════════════════════════════════════════════════════════" "$C_RESET"
    printf '\n%sWorking directory:%s %s\n' "$C_BOLD" "$C_RESET" "$work_dir"
    printf '%sNext step:%s   cd %s\n' "$C_BOLD" "$C_RESET" "$work_dir"
    printf '%sWhen done:%s   gitdrill validate\n' "$C_BOLD" "$C_RESET"
    printf '%sReset:%s       gitdrill reset\n\n' "$C_BOLD" "$C_RESET"
}

cmd_validate() {
    local drill_dir
    drill_dir=$(_gd_current_drill)
    [[ -n "$drill_dir" ]] || _gd_die "Not inside a drill. Run 'gitdrill start NNN' first."
    local work_dir
    work_dir=$(_gd_work_dir "$drill_dir")
    local validate="${drill_dir}/validate.sh"
    [[ -f "$validate" ]] || _gd_die "Missing validate.sh in $drill_dir"
    [[ -d "$work_dir" ]] || _gd_die "Working dir gone: $work_dir. Run 'gitdrill reset'."

    printf '%sValidating drill %s ...%s\n\n' "$C_BOLD" "$(basename "$drill_dir")" "$C_RESET"

    # Run validate.sh from inside the working dir; it gets these env vars:
    #   GD_WORK_DIR  - the seeded repo
    #   GD_PASS / GD_FAIL - shell functions for checks
    (
        cd "$work_dir" || exit 1
        export GD_WORK_DIR="$work_dir"
        bash "$validate"
    )
    local rc=$?
    echo
    if [[ $rc -eq 0 ]]; then
        _gd_ok "Drill passed."
        printf 'Run %sgitdrill show%s to see the solution walkthrough.\n' "$C_BOLD" "$C_RESET"
    else
        _gd_fail "Drill not yet complete."
        printf 'Run %sgitdrill reset%s to start over, or keep trying.\n' "$C_BOLD" "$C_RESET"
    fi
    return $rc
}

cmd_reset() {
    local drill_dir
    drill_dir=$(_gd_current_drill)
    [[ -n "$drill_dir" ]] || _gd_die "No current drill. Run 'gitdrill start NNN' first."

    # If the user is currently INSIDE the working dir we're about to nuke,
    # warn them they'll need to cd back in afterwards.
    local work_dir
    work_dir=$(_gd_work_dir "$drill_dir")
    local pwd_real
    pwd_real=$(pwd -P 2>/dev/null || echo "")
    local need_cd_back=0
    if [[ "$pwd_real" == "$work_dir"* ]]; then
        need_cd_back=1
    fi

    cmd_start "$(basename "$drill_dir" | cut -d- -f1)"

    if [[ $need_cd_back -eq 1 ]]; then
        printf '%sNOTE:%s Your shell is still in the OLD working dir (now deleted).\n' "$C_YELLOW" "$C_RESET"
        printf '      Run: %scd %s%s\n\n' "$C_BOLD" "$work_dir" "$C_RESET"
    fi
}

cmd_show() {
    local num="${1:-}"
    local drill_dir
    if [[ -n "$num" ]]; then
        drill_dir=$(_gd_find_drill "$num")
    else
        drill_dir=$(_gd_current_drill)
        [[ -n "$drill_dir" ]] || _gd_die "No current drill. Usage: gitdrill show NNN"
    fi
    local solution="${drill_dir}/SOLUTION.md"
    [[ -f "$solution" ]] || _gd_die "No SOLUTION.md in $drill_dir"
    if command -v less >/dev/null 2>&1; then
        less -R "$solution"
    else
        cat "$solution"
    fi
}

cmd_where() {
    local drill_dir
    drill_dir=$(_gd_current_drill)
    [[ -n "$drill_dir" ]] || _gd_die "No current drill."
    _gd_work_dir "$drill_dir"
}

cmd_help() {
    cat <<'EOF'
gitdrill - git practice drill runner

USAGE
  gitdrill list              List all drills
  gitdrill start NNN         Seed and start drill NNN (e.g. gitdrill start 1)
  gitdrill validate          Check whether the current drill is solved
  gitdrill reset             Re-seed the current drill from scratch
  gitdrill show [NNN]        Print the solution walkthrough
  gitdrill where             Print the current drill's working directory
  gitdrill help              Show this

WORKFLOW
  $ gitdrill start 1
  $ cd /tmp/gitdrill-001-staging-basics
  ... do real git commands ...
  $ gitdrill validate
  $ gitdrill show            # read the walkthrough
EOF
}

main() {
    local cmd="${1:-help}"
    shift || true
    case "$cmd" in
        list)     cmd_list "$@" ;;
        start)    cmd_start "$@" ;;
        validate) cmd_validate "$@" ;;
        reset)    cmd_reset "$@" ;;
        show)     cmd_show "$@" ;;
        where)    cmd_where "$@" ;;
        help|-h|--help) cmd_help ;;
        *)        _gd_die "Unknown command: $cmd. Try 'gitdrill help'." ;;
    esac
}

main "$@"
