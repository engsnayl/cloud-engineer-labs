#!/bin/bash
# =============================================================================
# Cloud Engineer Lab Runner
# A CLI tool for managing and running self-directed engineering labs
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
PROGRESS_FILE="$REPO_DIR/.lab-progress.json"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ---- Helpers ----

print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║          ☁️  Cloud Engineer Lab Runner  ☁️           ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_help() {
    print_banner
    echo -e "${BOLD}Usage:${NC}"
    echo "  labrunner.sh <command> [options]"
    echo ""
    echo -e "${BOLD}Commands:${NC}"
    echo "  list                    List all available labs"
    echo "  start <lab-path>        Start a specific lab"
    echo "  random [linux|cloud]    Start a random lab (optionally filter by type)"
    echo "  validate <lab-path>     Run validation for a lab"
    echo "  reset <lab-path>        Reset/restart a lab"
    echo "  progress                Show your progress and completion times"
    echo "  hint <lab-path>         Show hints for a lab"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo "  ./tools/labrunner.sh list"
    echo "  ./tools/labrunner.sh start linux-labs/lab-001-nginx-down"
    echo "  ./tools/labrunner.sh random linux"
    echo "  ./tools/labrunner.sh validate linux-labs/lab-001-nginx-down"
}

init_progress() {
    if [[ ! -f "$PROGRESS_FILE" ]]; then
        echo '{"labs":{}}' > "$PROGRESS_FILE"
    fi
}

record_start() {
    local lab_name="$1"
    init_progress
    local now=$(date +%s)
    local tmp=$(mktemp)
    if command -v python3 &>/dev/null; then
        python3 -c "
import json, sys
with open('$PROGRESS_FILE') as f:
    data = json.load(f)
data['labs'].setdefault('$lab_name', {})
data['labs']['$lab_name']['last_started'] = $now
data['labs']['$lab_name']['attempts'] = data['labs']['$lab_name'].get('attempts', 0) + 1
with open('$tmp', 'w') as f:
    json.dump(data, f, indent=2)
"
        mv "$tmp" "$PROGRESS_FILE"
    fi
}

record_completion() {
    local lab_name="$1"
    local duration="$2"
    init_progress
    local tmp=$(mktemp)
    if command -v python3 &>/dev/null; then
        python3 -c "
import json
with open('$PROGRESS_FILE') as f:
    data = json.load(f)
lab = data['labs'].setdefault('$lab_name', {})
lab['completed'] = True
lab['last_duration_seconds'] = $duration
best = lab.get('best_duration_seconds', 999999)
if $duration < best:
    lab['best_duration_seconds'] = $duration
with open('$tmp', 'w') as f:
    json.dump(data, f, indent=2)
"
        mv "$tmp" "$PROGRESS_FILE"
    fi
}

format_duration() {
    local seconds=$1
    printf "%dm %ds" $((seconds / 60)) $((seconds % 60))
}

get_lab_metadata() {
    local lab_path="$1"
    local field="$2"
    local challenge_file="$REPO_DIR/$lab_path/CHALLENGE.md"
    if [[ -f "$challenge_file" ]]; then
        grep "^$field:" "$challenge_file" | head -1 | sed "s/^$field: *//"
    fi
}

# ---- Commands ----

cmd_list() {
    print_banner
    init_progress

    echo -e "${BOLD}${BLUE}Linux Troubleshooting Labs${NC}"
    echo -e "${BLUE}──────────────────────────${NC}"
    for lab_dir in "$REPO_DIR"/linux-labs/lab-*/; do
        if [[ -d "$lab_dir" ]]; then
            local lab_name=$(basename "$lab_dir")
            local lab_path="linux-labs/$lab_name"
            local title=$(get_lab_metadata "$lab_path" "Title")
            local difficulty=$(get_lab_metadata "$lab_path" "Difficulty")
            local time_est=$(get_lab_metadata "$lab_path" "Time")

            # Check completion status
            local status="⬡"
            if command -v python3 &>/dev/null && [[ -f "$PROGRESS_FILE" ]]; then
                local completed=$(python3 -c "
import json
with open('$PROGRESS_FILE') as f:
    data = json.load(f)
print(data.get('labs',{}).get('$lab_path',{}).get('completed', False))
" 2>/dev/null || echo "False")
                if [[ "$completed" == "True" ]]; then
                    status="${GREEN}✔${NC}"
                fi
            fi

            echo -e "  $status  ${BOLD}$lab_name${NC} — ${title:-Untitled}"
            echo -e "     Difficulty: ${difficulty:-?} | Est: ${time_est:-?}"
        fi
    done

    echo ""
    echo -e "${BOLD}${BLUE}Cloud Infrastructure Labs${NC}"
    echo -e "${BLUE}─────────────────────────${NC}"
    for lab_dir in "$REPO_DIR"/cloud-labs/lab-*/; do
        if [[ -d "$lab_dir" ]]; then
            local lab_name=$(basename "$lab_dir")
            local lab_path="cloud-labs/$lab_name"
            local title=$(get_lab_metadata "$lab_path" "Title")
            local difficulty=$(get_lab_metadata "$lab_path" "Difficulty")
            local time_est=$(get_lab_metadata "$lab_path" "Time")

            local status="⬡"
            if command -v python3 &>/dev/null && [[ -f "$PROGRESS_FILE" ]]; then
                local completed=$(python3 -c "
import json
with open('$PROGRESS_FILE') as f:
    data = json.load(f)
print(data.get('labs',{}).get('$lab_path',{}).get('completed', False))
" 2>/dev/null || echo "False")
                if [[ "$completed" == "True" ]]; then
                    status="${GREEN}✔${NC}"
                fi
            fi

            echo -e "  $status  ${BOLD}$lab_name${NC} — ${title:-Untitled}"
            echo -e "     Difficulty: ${difficulty:-?} | Est: ${time_est:-?}"
        fi
    done
    echo ""
}

cmd_start() {
    local lab_path="${1:-}"
    if [[ -z "$lab_path" ]]; then
        echo -e "${RED}Error: Specify a lab path, e.g. linux-labs/lab-001-nginx-down${NC}"
        exit 1
    fi

    local full_path="$REPO_DIR/$lab_path"
    if [[ ! -d "$full_path" ]]; then
        echo -e "${RED}Error: Lab not found at $lab_path${NC}"
        exit 1
    fi

    local challenge_file="$full_path/CHALLENGE.md"
    if [[ ! -f "$challenge_file" ]]; then
        echo -e "${RED}Error: No CHALLENGE.md found in $lab_path${NC}"
        exit 1
    fi

    print_banner

    local title=$(get_lab_metadata "$lab_path" "Title")
    local difficulty=$(get_lab_metadata "$lab_path" "Difficulty")
    local time_est=$(get_lab_metadata "$lab_path" "Time")
    local category=$(get_lab_metadata "$lab_path" "Category")

    echo -e "${BOLD}${YELLOW}Starting Lab: $title${NC}"
    echo -e "Difficulty: $difficulty | Estimated Time: $time_est | Category: $category"
    echo -e "${BLUE}──────────────────────────────────────────────────${NC}"
    echo ""

    # Print the scenario section of the challenge file
    sed -n '/^## Scenario/,/^## /{ /^## Scenario/d; /^## [^S]/d; p; }' "$challenge_file"
    echo ""

    echo -e "${BLUE}──────────────────────────────────────────────────${NC}"

    # Determine lab type and start accordingly
    if [[ "$lab_path" == linux-labs/* ]]; then
        echo -e "${CYAN}Building and starting Docker environment...${NC}"
        cd "$full_path"
        docker compose down 2>/dev/null || true
        docker compose build --quiet
        docker compose up -d
        echo ""
        echo -e "${GREEN}Lab environment is running.${NC}"
        echo ""
        echo -e "${BOLD}To enter the environment:${NC}"
        local container_name=$(docker compose ps --format '{{.Names}}' | head -1)
        echo -e "  docker exec -it $container_name bash"
        echo ""
        echo -e "${BOLD}When you think you've fixed it:${NC}"
        echo -e "  ./tools/labrunner.sh validate $lab_path"
        echo ""
        echo -e "${BOLD}Need a hint?${NC}"
        echo -e "  ./tools/labrunner.sh hint $lab_path"
    elif [[ "$lab_path" == cloud-labs/* ]]; then
        echo -e "${CYAN}This is a cloud lab. Review the CHALLENGE.md then:${NC}"
        echo ""
        echo -e "  cd $lab_path"
        echo -e "  terraform init"
        echo -e "  terraform apply"
        echo ""
        echo -e "Then diagnose and fix the infrastructure."
    fi

    record_start "$lab_path"
    echo ""
    echo -e "${YELLOW}⏱  Timer started. Good luck!${NC}"
}

cmd_validate() {
    local lab_path="${1:-}"
    if [[ -z "$lab_path" ]]; then
        echo -e "${RED}Error: Specify a lab path${NC}"
        exit 1
    fi

    local full_path="$REPO_DIR/$lab_path"
    local validate_script="$full_path/validate.sh"

    if [[ ! -f "$validate_script" ]]; then
        echo -e "${RED}Error: No validate.sh found in $lab_path${NC}"
        exit 1
    fi

    print_banner
    echo -e "${CYAN}Running validation for: $lab_path${NC}"
    echo -e "${BLUE}──────────────────────────────────────────────────${NC}"
    echo ""

    # Calculate duration from start time
    local start_time=""
    if command -v python3 &>/dev/null && [[ -f "$PROGRESS_FILE" ]]; then
        start_time=$(python3 -c "
import json
with open('$PROGRESS_FILE') as f:
    data = json.load(f)
print(data.get('labs',{}).get('$lab_path',{}).get('last_started', ''))
" 2>/dev/null || echo "")
    fi

    chmod +x "$validate_script"
    if bash "$validate_script"; then
        echo ""
        echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║  ✅  ALL CHECKS PASSED — WELL DONE! ║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"

        if [[ -n "$start_time" ]]; then
            local now=$(date +%s)
            local duration=$((now - start_time))
            echo -e "  Completion time: $(format_duration $duration)"
            record_completion "$lab_path" "$duration"
        fi
    else
        echo ""
        echo -e "${RED}╔══════════════════════════════════════╗${NC}"
        echo -e "${RED}║  ❌  SOME CHECKS FAILED — TRY AGAIN ║${NC}"
        echo -e "${RED}╚══════════════════════════════════════╝${NC}"
    fi
    echo ""
}

cmd_reset() {
    local lab_path="${1:-}"
    if [[ -z "$lab_path" ]]; then
        echo -e "${RED}Error: Specify a lab path${NC}"
        exit 1
    fi

    local full_path="$REPO_DIR/$lab_path"

    if [[ "$lab_path" == linux-labs/* ]]; then
        echo -e "${CYAN}Resetting lab environment...${NC}"
        cd "$full_path"
        docker compose down 2>/dev/null || true
        docker compose build --quiet --no-cache
        docker compose up -d
        echo -e "${GREEN}Lab reset complete. Environment is fresh.${NC}"
    elif [[ "$lab_path" == cloud-labs/* ]]; then
        echo -e "${CYAN}Destroying cloud resources...${NC}"
        cd "$full_path"
        terraform destroy -auto-approve
        echo -e "${GREEN}Cloud resources destroyed. Run 'terraform apply' to start again.${NC}"
    fi
}

cmd_hint() {
    local lab_path="${1:-}"
    if [[ -z "$lab_path" ]]; then
        echo -e "${RED}Error: Specify a lab path${NC}"
        exit 1
    fi

    local hints_file="$REPO_DIR/$lab_path/HINTS.md"
    if [[ ! -f "$hints_file" ]]; then
        echo -e "${RED}No hints available for this lab.${NC}"
        exit 1
    fi

    echo -e "${YELLOW}⚠  Are you sure? Hints reduce the learning value.${NC}"
    read -p "Show hints? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cat "$hints_file"
    fi
}

cmd_random() {
    local filter="${1:-all}"
    local labs=()

    if [[ "$filter" == "linux" || "$filter" == "all" ]]; then
        for d in "$REPO_DIR"/linux-labs/lab-*/; do
            [[ -d "$d" ]] && labs+=("linux-labs/$(basename "$d")")
        done
    fi
    if [[ "$filter" == "cloud" || "$filter" == "all" ]]; then
        for d in "$REPO_DIR"/cloud-labs/lab-*/; do
            [[ -d "$d" ]] && labs+=("cloud-labs/$(basename "$d")")
        done
    fi

    if [[ ${#labs[@]} -eq 0 ]]; then
        echo -e "${RED}No labs found.${NC}"
        exit 1
    fi

    local random_lab="${labs[$RANDOM % ${#labs[@]}]}"
    echo -e "${CYAN}Randomly selected: $random_lab${NC}"
    echo ""
    cmd_start "$random_lab"
}

cmd_progress() {
    print_banner
    init_progress

    if ! command -v python3 &>/dev/null; then
        echo -e "${RED}Python3 required for progress tracking.${NC}"
        exit 1
    fi

    python3 -c "
import json

with open('$PROGRESS_FILE') as f:
    data = json.load(f)

labs = data.get('labs', {})
if not labs:
    print('  No labs attempted yet. Get started with: ./tools/labrunner.sh random')
else:
    completed = sum(1 for l in labs.values() if l.get('completed'))
    total = len(labs)
    print(f'  Labs attempted: {total}')
    print(f'  Labs completed: {completed}')
    print()
    print(f'  {\"Lab\":<45} {\"Status\":<10} {\"Best Time\":<12} {\"Attempts\"}')
    print(f'  {\"─\"*45} {\"─\"*10} {\"─\"*12} {\"─\"*8}')
    for name, info in sorted(labs.items()):
        status = '✅' if info.get('completed') else '🔄'
        best = info.get('best_duration_seconds', 0)
        best_str = f'{best//60}m {best%60}s' if best else '—'
        attempts = info.get('attempts', 0)
        print(f'  {name:<45} {status:<10} {best_str:<12} {attempts}')
"
    echo ""
}

# ---- Main ----

case "${1:-help}" in
    list)       cmd_list ;;
    start)      cmd_start "${2:-}" ;;
    validate)   cmd_validate "${2:-}" ;;
    reset)      cmd_reset "${2:-}" ;;
    hint)       cmd_hint "${2:-}" ;;
    random)     cmd_random "${2:-all}" ;;
    progress)   cmd_progress ;;
    help|*)     print_help ;;
esac
