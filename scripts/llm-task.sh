#!/bin/bash

# LLM Task Runner - Supports Gemini, Codex, Qwen
# Usage:
#   llm-task.sh [-b backend] [-m model] [-B] "task"     # Single task
#   llm-task.sh --swarm "task1" "task2" "task3"         # Parallel swarm
#
# Options:
#   -B          Run in background (returns immediately with PID)
#   --swarm     Run multiple tasks in parallel (each auto-routed)

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Defaults
BACKEND="auto"
MODEL=""
TIMEOUT_MIN=5
QUIET=false
BACKGROUND=true   # Default: run in background
FOREGROUND=false  # -F flag to force foreground
TASK=""

# Output directory for background tasks
OUTPUT_DIR="/tmp/llm-manager-tasks"
mkdir -p "$OUTPUT_DIR"

usage() {
    echo "Usage: $0 [-b backend] [-m model] [-F] [-q] task"
    echo "       $0 --swarm 'task1' 'task2' 'task3'"
    echo "       $0 --brainstorm 'task'"
    echo ""
    echo "Backends: gemini, codex, qwen, claude, auto (default)"
    echo ""
    echo "Options:"
    echo "  -b backend   : gemini, codex, qwen, claude, or auto"
    echo "  -m model     : Model override (backend-specific)"
    echo "  -F           : Force foreground (default is background)"
    echo "  -q           : Quiet mode"
    echo "  --swarm      : Run multiple tasks in parallel (smart routed)"
    echo "  --brainstorm : All agents work on same task (diverse perspectives)"
    echo "  --collect    : Collect and display brainstorm results"
    echo "  --collect --md : Save brainstorm results to markdown file"
    echo "  --status     : Check status of background tasks"
    echo ""
    echo "Examples:"
    echo "  $0 'Create a hello world script'       # Background, smart routed"
    echo "  $0 -F 'Quick task'                     # Foreground (wait)"
    echo "  $0 --swarm 'task1' 'task2' 'task3'     # Parallel swarm"
    echo "  $0 --brainstorm 'How should we architect this feature?'"
    echo "  $0 --status                            # Check running tasks"
    exit 1
}

# Swarm mode: run multiple tasks in parallel
run_swarm() {
    local pids=()
    local tasks=("$@")

    echo -e "${CYAN}=== SWARM MODE: Dispatching ${#tasks[@]} interns ===${NC}"

    for task in "${tasks[@]}"; do
        # Get the backend for this task
        local backend=$(smart_select_backend "$task")
        local role
        case "$backend" in
            gemini) role="Creative/Fast" ;;
            codex)  role="Senior" ;;
            qwen)   role="Research" ;;
            claude) role="Architect" ;;
            *)      role="Unknown" ;;
        esac

        # Create output file
        local task_id=$(date +%s%N | md5sum | head -c 8)
        local output_file="$OUTPUT_DIR/$task_id.out"
        local task_short=$(echo "$task" | head -c 40)

        echo -e "${GREEN}[$task_id] $backend ($role): $task_short...${NC}"

        # Run in background
        (
            case "$backend" in
                gemini) gemini "$task" --yolo -o text > "$output_file" 2>&1 ;;
                codex)  codex exec "$task" -s danger-full-access --skip-git-repo-check > "$output_file" 2>&1 ;;
                qwen)   qwen "$task" --yolo > "$output_file" 2>&1 ;;
                claude) claude -p "$task" --dangerously-skip-permissions > "$output_file" 2>&1 ;;
            esac
            echo "DONE" >> "$output_file"
        ) &

        pids+=($!)
        echo "$!" > "$OUTPUT_DIR/$task_id.pid"
        echo "$task" > "$OUTPUT_DIR/$task_id.task"
        echo "$backend" > "$OUTPUT_DIR/$task_id.backend"
    done

    echo ""
    echo -e "${CYAN}Swarm dispatched! ${#pids[@]} tasks running in background.${NC}"
    echo -e "Task IDs: ${pids[*]}"
    echo -e "Check status: $0 --status"
    echo -e "Outputs in: $OUTPUT_DIR/"
}

# Check status of background tasks
check_status() {
    echo -e "${CYAN}=== Background Task Status ===${NC}"
    local found=false

    for pidfile in "$OUTPUT_DIR"/*.pid; do
        [ -f "$pidfile" ] || continue
        found=true

        local task_id=$(basename "$pidfile" .pid)
        local pid=$(cat "$pidfile")
        local backend=$(cat "$OUTPUT_DIR/$task_id.backend" 2>/dev/null || echo "unknown")
        local task=$(cat "$OUTPUT_DIR/$task_id.task" 2>/dev/null | head -c 50)
        local output_file="$OUTPUT_DIR/$task_id.out"

        if kill -0 "$pid" 2>/dev/null; then
            echo -e "${YELLOW}[$task_id] RUNNING${NC} - $backend: $task..."
        else
            if grep -q "DONE" "$output_file" 2>/dev/null; then
                echo -e "${GREEN}[$task_id] DONE${NC} - $backend: $task..."
            else
                echo -e "${RED}[$task_id] FAILED${NC} - $backend: $task..."
            fi
            # Cleanup completed task markers
            rm -f "$pidfile"
        fi
    done

    if [ "$found" = false ]; then
        echo "No background tasks found."
    fi
}

detect_available() {
    local available=""
    command -v gemini >/dev/null 2>&1 && available="$available gemini"
    command -v codex >/dev/null 2>&1 && available="$available codex"
    command -v qwen >/dev/null 2>&1 && available="$available qwen"
    command -v claude >/dev/null 2>&1 && available="$available claude"
    echo "$available"
}

smart_select_backend() {
    local task="$1"
    local available=$(detect_available)
    local task_lower=$(echo "$task" | tr '[:upper:]' '[:lower:]')

    # ==============================================
    # INTERN ROLES:
    # - GEMINI  = "Creative/Fast Intern" - images, video, quick tasks
    # - CODEX   = "Senior Intern" - complex reasoning, code review, debugging
    # - QWEN    = "Research Intern" - large codebases, thorough analysis
    # ==============================================

    # GEMINI: Creative/Fast Intern - images, video, quick tasks
    local gemini_pattern="generate image|create image|make image|draw|image of|picture of|logo|icon|illustration|graphic|video|animation|clip|quick|fast|simple"

    # CODEX: Senior Intern - complex reasoning, code review, debugging
    local codex_pattern="refactor|redesign|architect|restructure|complex|tricky|difficult|challenging|analyze|debug|investigate|diagnose|review|code review|pr review|pull request|screenshot|wireframe|mockup|ui design|from image|algorithm|optimize|performance|security|vulnerability|audit|multi-step|multi-file|across files"

    # QWEN: Research Intern - large codebases, thorough analysis
    local qwen_pattern="entire|whole|all files|codebase|full project|large|massive|huge|extensive|migrate|convert|port|understand codebase|explain architecture|summarize project|thorough|comprehensive|free|budget|cost-effective"

    # CLAUDE: Architect - planning, orchestration, nuanced decisions
    local claude_pattern="plan|orchestrate|coordinate|multi-step|breakdown|strategy|design|decide|evaluate|compare|trade-off|nuanced|architect|lead"

    # 1. Creative tasks → Gemini (only one that can generate images/video)
    if [[ "$available" == *"gemini"* ]] && echo "$task_lower" | grep -qiE "$gemini_pattern"; then
        echo "gemini"
        return
    fi

    # 2. Complex/Senior tasks → Codex (best reasoning)
    if [[ "$available" == *"codex"* ]] && echo "$task_lower" | grep -qiE "$codex_pattern"; then
        echo "codex"
        return
    fi

    # 3. Research/Large context tasks → Qwen (best context window)
    if [[ "$available" == *"qwen"* ]] && echo "$task_lower" | grep -qiE "$qwen_pattern"; then
        echo "qwen"
        return
    fi

    # 4. Planning/Orchestration → Claude (best at nuanced reasoning)
    if [[ "$available" == *"claude"* ]] && echo "$task_lower" | grep -qiE "$claude_pattern"; then
        echo "claude"
        return
    fi

    # 5. Default: first available (fallback)
    echo "$available" | tr ' ' '\n' | grep -v '^$' | head -1
}

run_claude() {
    local task="$1"
    local args=("-p" "$task" "--dangerously-skip-permissions")

    if [ "$QUIET" = true ]; then
        claude "${args[@]}" 2>/dev/null
    else
        claude "${args[@]}" 2>&1
    fi
}

run_gemini() {
    local task="$1"
    local args=("--yolo" "-o" "text")

    [ -n "$MODEL" ] && args+=("-m" "$MODEL")
    args+=("$task")

    if [ "$QUIET" = true ]; then
        gemini "${args[@]}" 2>/dev/null
    else
        gemini "${args[@]}" 2>&1
    fi
}

run_codex() {
    local task="$1"
    local args=("-s" "danger-full-access" "--skip-git-repo-check")

    [ -n "$MODEL" ] && args+=("-m" "$MODEL")
    args+=("$task")

    if [ "$QUIET" = true ]; then
        codex exec "${args[@]}" 2>/dev/null
    else
        codex exec "${args[@]}" 2>&1
    fi
}

run_qwen() {
    local task="$1"
    local args=("--yolo")

    [ -n "$MODEL" ] && args+=("-m" "$MODEL")
    args+=("$task")

    if [ "$QUIET" = true ]; then
        qwen "${args[@]}" 2>/dev/null
    else
        qwen "${args[@]}" 2>&1
    fi
}

# Brainstorm mode: all agents work on same task
run_brainstorm() {
    local task="$1"
    local available=$(detect_available)
    local pids=()

    echo -e "${CYAN}=== BRAINSTORM MODE: All agents working on same task ===${NC}"
    echo -e "Task: ${task:0:60}..."
    echo ""

    for backend in $available; do
        local task_id=$(date +%s%N | md5sum | head -c 8)
        local output_file="$OUTPUT_DIR/$task_id.out"
        local role
        case "$backend" in
            gemini) role="Creative/Fast" ;;
            codex)  role="Senior" ;;
            qwen)   role="Research" ;;
            claude) role="Architect" ;;
            *)      role="Agent" ;;
        esac

        echo -e "${GREEN}[$task_id] $backend ($role)${NC}"

        (
            case "$backend" in
                gemini) gemini "$task" --yolo -o text > "$output_file" 2>&1 ;;
                codex)  codex exec "$task" -s danger-full-access --skip-git-repo-check > "$output_file" 2>&1 ;;
                qwen)   qwen "$task" --yolo > "$output_file" 2>&1 ;;
                claude) claude -p "$task" --dangerously-skip-permissions > "$output_file" 2>&1 ;;
            esac
            echo "DONE:$backend" >> "$output_file"
        ) &

        pids+=($!)
        echo "$!" > "$OUTPUT_DIR/$task_id.pid"
        echo "$task" > "$OUTPUT_DIR/$task_id.task"
        echo "$backend" > "$OUTPUT_DIR/$task_id.backend"
    done

    echo ""
    echo -e "${CYAN}Brainstorm started! ${#pids[@]} agents working in parallel.${NC}"
    echo -e "Check status: $0 --status"
    echo -e "Outputs in: $OUTPUT_DIR/"
}

# Handle special commands first
case "${1:-}" in
    --swarm)
        shift
        if [ $# -lt 1 ]; then
            echo -e "${RED}Error: --swarm requires at least one task${NC}" >&2
            usage
        fi
        run_swarm "$@"
        exit 0
        ;;
    --brainstorm)
        shift
        if [ $# -lt 1 ]; then
            echo -e "${RED}Error: --brainstorm requires a task${NC}" >&2
            usage
        fi
        run_brainstorm "$*"
        exit 0
        ;;
    --status)
        check_status
        exit 0
        ;;
    --clear)
        rm -f "$OUTPUT_DIR"/*.out "$OUTPUT_DIR"/*.pid "$OUTPUT_DIR"/*.task "$OUTPUT_DIR"/*.backend "$OUTPUT_DIR"/*.md 2>/dev/null
        echo -e "${GREEN}Cleared all task files${NC}"
        exit 0
        ;;
    --collect)
        shift
        MD_OUT=""
        [ "$1" = "--md" ] && MD_OUT="/tmp/llm-manager-tasks/brainstorm-$(date +%Y%m%d-%H%M%S).md"

        # Build output
        output=""
        output+="# Brainstorm Results\n\n"
        output+="Generated: $(date)\n\n"

        # Get the task (from any task file)
        task_file=$(ls "$OUTPUT_DIR"/*.task 2>/dev/null | head -1)
        if [ -f "$task_file" ]; then
            output+="## Question\n\n"
            output+="> $(cat "$task_file")\n\n"
        fi

        output+="## Agent Perspectives\n\n"

        for outfile in "$OUTPUT_DIR"/*.out; do
            [ -f "$outfile" ] || continue
            task_id=$(basename "$outfile" .out)
            backend_file="$OUTPUT_DIR/$task_id.backend"
            [ -f "$backend_file" ] || continue
            backend=$(cat "$backend_file")

            case "$backend" in
                gemini) role="Creative/Fast" ;;
                codex)  role="Senior" ;;
                qwen)   role="Research" ;;
                claude) role="Architect" ;;
                *)      role="Agent" ;;
            esac

            output+="### $backend ($role)\n\n"
            # Filter noise from each backend
            content=$(grep -v "^DONE" "$outfile" | \
                grep -v "^YOLO mode" | grep -v "^Session cleanup" | grep -v "^Loaded cached" | grep -v "^Server '" | \
                grep -v "^OpenAI Codex" | grep -v "^--------" | grep -v "^workdir:" | grep -v "^model:" | \
                grep -v "^provider:" | grep -v "^approval:" | grep -v "^sandbox:" | grep -v "^reasoning" | \
                grep -v "^session id:" | grep -v "^mcp startup" | grep -v "^tokens used" | grep -v "^user$" | \
                grep -v "^thinking$" | grep -v "^codex$" | grep -v "^\*\*" | \
                tail -10)
            output+="\`\`\`\n$content\n\`\`\`\n\n"
        done

        # Agreement analysis
        total=$(ls "$OUTPUT_DIR"/*.backend 2>/dev/null | wc -l)
        done_count=$(grep -l "DONE" "$OUTPUT_DIR"/*.out 2>/dev/null | wc -l)
        output+="## Summary\n\n"
        output+="- **Completed**: $done_count / $total agents\n"
        output+="- **Timestamp**: $(date)\n"

        if [ -n "$MD_OUT" ]; then
            echo -e "$output" > "$MD_OUT"
            echo -e "${GREEN}Saved to: $MD_OUT${NC}"
        else
            echo -e "$output"
        fi
        exit 0
        ;;
esac

# Parse options
while getopts ":b:m:t:qF" opt; do
    case ${opt} in
        b) BACKEND="${OPTARG}" ;;
        m) MODEL="${OPTARG}" ;;
        t) TIMEOUT_MIN="${OPTARG}" ;;
        q) QUIET=true ;;
        F) FOREGROUND=true; BACKGROUND=false ;;
        \?) echo "Invalid option: -${OPTARG}" >&2; usage ;;
        :) echo "Option -${OPTARG} requires an argument." >&2; usage ;;
    esac
done
shift $((OPTIND -1))

# Get task
if [ $# -ge 1 ]; then
    TASK="$*"
elif [ ! -t 0 ]; then
    TASK=$(cat)
fi

if [ -z "$TASK" ]; then
    echo -e "${RED}Error: No task provided.${NC}" >&2
    usage
fi

# Validate timeout
if ! [[ "$TIMEOUT_MIN" =~ ^[0-9]+$ ]] || [ "$TIMEOUT_MIN" -gt 10 ]; then
    [ "$TIMEOUT_MIN" -gt 10 ] && echo "Warning: Capping timeout at 10 minutes." >&2
    TIMEOUT_MIN=10
fi

# Select backend using smart heuristics
if [ "$BACKEND" = "auto" ]; then
    BACKEND=$(smart_select_backend "$TASK")
    if [ -z "$BACKEND" ]; then
        echo -e "${RED}Error: No supported backend found.${NC}" >&2
        echo "Install one of: gemini, codex, qwen" >&2
        exit 1
    fi
    if [ "$QUIET" = false ]; then
        # Explain why this backend was chosen (with role)
        case "$BACKEND" in
            gemini) ROLE="Creative/Fast" ;;
            codex)  ROLE="Senior" ;;
            qwen)   ROLE="Research" ;;
            claude) ROLE="Architect" ;;
            *)      ROLE="Agent" ;;
        esac
        echo -e "${GREEN}Smart routing → $BACKEND ($ROLE)${NC}" >&2
    fi
fi

# Background mode: run task in background
if [ "$BACKGROUND" = true ]; then
    task_id=$(date +%s%N | md5sum | head -c 8)
    output_file="$OUTPUT_DIR/$task_id.out"
    task_short=$(echo "$TASK" | head -c 50)

    echo -e "${CYAN}Background task started: $task_id${NC}"
    echo -e "Backend: $BACKEND | Output: $output_file"

    (
        case "$BACKEND" in
            gemini) run_gemini "$TASK" > "$output_file" 2>&1 ;;
            codex)  run_codex "$TASK" > "$output_file" 2>&1 ;;
            qwen)   run_qwen "$TASK" > "$output_file" 2>&1 ;;
            claude) run_claude "$TASK" > "$output_file" 2>&1 ;;
        esac
        echo "DONE" >> "$output_file"
    ) &

    echo "$!" > "$OUTPUT_DIR/$task_id.pid"
    echo "$TASK" > "$OUTPUT_DIR/$task_id.task"
    echo "$BACKEND" > "$OUTPUT_DIR/$task_id.backend"

    echo -e "PID: $!"
    echo -e "Check status: $0 --status"
    exit 0
fi

# Run the appropriate backend (foreground)
case "$BACKEND" in
    gemini)
        if ! command -v gemini >/dev/null 2>&1; then
            echo -e "${RED}Error: gemini not found${NC}" >&2
            exit 1
        fi
        run_gemini "$TASK"
        ;;
    codex)
        if ! command -v codex >/dev/null 2>&1; then
            echo -e "${RED}Error: codex not found${NC}" >&2
            exit 1
        fi
        run_codex "$TASK"
        ;;
    qwen)
        if ! command -v qwen >/dev/null 2>&1; then
            echo -e "${RED}Error: qwen not found${NC}" >&2
            exit 1
        fi
        run_qwen "$TASK"
        ;;
    claude)
        if ! command -v claude >/dev/null 2>&1; then
            echo -e "${RED}Error: claude not found${NC}" >&2
            exit 1
        fi
        run_claude "$TASK"
        ;;
    *)
        echo -e "${RED}Error: Unknown backend '$BACKEND'${NC}" >&2
        echo "Supported: gemini, codex, qwen, claude" >&2
        exit 1
        ;;
esac

exit $?
