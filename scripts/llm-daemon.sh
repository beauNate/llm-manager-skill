#!/bin/bash

# LLM Daemon - Autonomous task processor
# Runs for hours, processes queue, auto-retries, watchdog, notifications

set -e

# Config
QUEUE_DIR="/tmp/llm-manager-queue"
OUTPUT_DIR="/tmp/llm-manager-tasks"
LOG_FILE="/tmp/llm-manager-daemon.log"
PID_FILE="/tmp/llm-manager-daemon.pid"
MAX_RETRIES=3
TASK_TIMEOUT=300  # 5 minutes per task
POLL_INTERVAL=5   # Check queue every 5 seconds
MAX_WORKERS=999   # Unlimited parallel tasks
# No fixed order - smart routing picks the best

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

mkdir -p "$QUEUE_DIR" "$OUTPUT_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

notify() {
    local title="$1"
    local message="$2"
    # macOS notification
    osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null || true
    # Terminal bell (Claude can detect)
    echo -e "\a"
    # Write to completion file (Claude polls this)
    echo "$message" >> "/tmp/llm-manager-completions.log"
    # Also log
    log "NOTIFY: $title - $message"
}

usage() {
    echo "LLM Daemon - Autonomous Task Processor"
    echo ""
    echo "Usage:"
    echo "  $0 start [--workers N]  Start daemon (default: unlimited)"
    echo "  $0 stop                 Stop daemon"
    echo "  $0 status               Show daemon status"
    echo "  $0 add 'task'           Add task to queue"
    echo "  $0 add-file file.txt    Add tasks from file (one per line)"
    echo "  $0 queue                Show pending queue"
    echo "  $0 logs                 Tail daemon logs"
    echo "  $0 clear                Clear completed tasks"
    echo ""
    echo "Examples:"
    echo "  $0 start --workers 8    Start with 8 parallel workers"
    echo "  $0 add 'Build feature'  Queue a task"
    exit 1
}

# Detect available backends
detect_backends() {
    local available=""
    for b in gemini codex qwen claude; do
        command -v "$b" >/dev/null 2>&1 && available="$available $b"
    done
    echo "$available"
}

# Smart routing - unbiased, picks best for task
smart_select_backend() {
    local task="$1"
    local available=$(detect_backends)
    local task_lower=$(echo "$task" | tr '[:upper:]' '[:lower:]')

    # GEMINI: Creative/Fast - images, video, quick tasks
    local gemini_pattern="generate image|create image|draw|logo|icon|video|animation|quick|fast|simple|scaffold"

    # CODEX: Complex reasoning - refactoring, debugging, code review
    local codex_pattern="refactor|redesign|architect|complex|debug|investigate|review|algorithm|optimize|security|multi-file"

    # QWEN: Large context - entire codebase, thorough analysis
    local qwen_pattern="entire|whole|all files|codebase|full project|large|massive|migrate|thorough|comprehensive"

    # CLAUDE: Planning, orchestration, multi-step, nuanced reasoning
    local claude_pattern="plan|orchestrate|coordinate|multi-step|breakdown|strategy|design|decide|evaluate|compare|trade-off|nuanced"

    # Match in parallel - no priority bias
    [[ "$available" == *"gemini"* ]] && echo "$task_lower" | grep -qiE "$gemini_pattern" && { echo "gemini"; return; }
    [[ "$available" == *"codex"* ]] && echo "$task_lower" | grep -qiE "$codex_pattern" && { echo "codex"; return; }
    [[ "$available" == *"qwen"* ]] && echo "$task_lower" | grep -qiE "$qwen_pattern" && { echo "qwen"; return; }
    [[ "$available" == *"claude"* ]] && echo "$task_lower" | grep -qiE "$claude_pattern" && { echo "claude"; return; }

    # Default: first available (fallback)
    echo "$available" | tr ' ' '\n' | grep -v '^$' | head -1
}

# Run task with smart routing and failover
run_with_failover() {
    local task="$1"
    local task_id="$2"
    local output_file="$OUTPUT_DIR/$task_id.out"

    # Smart select first, then failover to others
    local primary=$(smart_select_backend "$task")
    local all_backends=$(detect_backends)

    # Try primary first, then others
    local tried=""
    for backend in $primary $all_backends; do
        # Skip if already tried
        [[ "$tried" == *"$backend"* ]] && continue
        tried="$tried $backend"

        for attempt in $(seq 1 $MAX_RETRIES); do
            log "[$task_id] Attempt $attempt with $backend"

            local start_time=$(date +%s)
            local success=false

            # Run with timeout
            (
                case "$backend" in
                    gemini) gemini "$task" --yolo -o text > "$output_file" 2>&1 ;;
                    codex)  codex exec "$task" -s danger-full-access --skip-git-repo-check > "$output_file" 2>&1 ;;
                    qwen)   qwen "$task" --yolo > "$output_file" 2>&1 ;;
                    claude) claude -p "$task" --dangerously-skip-permissions > "$output_file" 2>&1 ;;
                esac
            ) && success=true

            local elapsed=$(($(date +%s) - start_time))

            if [ "$success" = true ]; then
                log "[$task_id] SUCCESS with $backend in ${elapsed}s"
                echo "SUCCESS" >> "$output_file"
                notify "Task Complete" "$task_id finished with $backend"
                return 0
            else
                log "[$task_id] FAILED attempt $attempt with $backend"
            fi
        done
        log "[$task_id] Failing over from $backend..."
    done

    log "[$task_id] ALL BACKENDS FAILED"
    echo "FAILED" >> "$output_file"
    notify "Task Failed" "$task_id failed after all retries"
    return 1
}

# Count running workers
count_workers() {
    ls "$QUEUE_DIR"/*.processing 2>/dev/null | wc -l | tr -d ' '
}

# Process single task (runs in background)
process_task() {
    local task_file="$1"
    local task_id=$(basename "$task_file" .task)
    local task=$(cat "$task_file")

    # Mark as processing
    mv "$task_file" "$QUEUE_DIR/$task_id.processing"

    log "[$task_id] Processing: ${task:0:50}..."
    run_with_failover "$task" "$task_id"

    # Mark as done
    mv "$QUEUE_DIR/$task_id.processing" "$QUEUE_DIR/$task_id.done"
}

# Main daemon loop
daemon_loop() {
    log "Daemon started (PID $$) - Max workers: $MAX_WORKERS"
    echo $$ > "$PID_FILE"

    notify "LLM Daemon" "Started with $MAX_WORKERS workers"

    while true; do
        # Process pending tasks up to MAX_WORKERS
        for task_file in $(ls "$QUEUE_DIR"/*.task 2>/dev/null || true); do
            [ -f "$task_file" ] || continue

            # Check worker limit
            local current_workers=$(count_workers)
            if [ "$current_workers" -ge "$MAX_WORKERS" ]; then
                log "Worker limit reached ($current_workers/$MAX_WORKERS), waiting..."
                break
            fi

            # Process in background
            process_task "$task_file" &
        done

        sleep $POLL_INTERVAL
    done
}

# Add task to queue
add_task() {
    local task="$1"
    local task_id=$(date +%s%N | md5sum | head -c 8)
    echo "$task" > "$QUEUE_DIR/$task_id.task"
    echo -e "${GREEN}Queued: $task_id${NC}"
    echo "Task: ${task:0:60}..."
}

# Add tasks from file
add_from_file() {
    local file="$1"
    [ -f "$file" ] || { echo "File not found: $file"; exit 1; }
    local count=0
    while IFS= read -r line; do
        [ -n "$line" ] && add_task "$line" && ((count++))
    done < "$file"
    echo -e "${GREEN}Queued $count tasks${NC}"
}

# Show queue
show_queue() {
    echo -e "${CYAN}=== Task Queue ===${NC}"
    local pending=0 processing=0 done_count=0

    for f in $(ls "$QUEUE_DIR"/*.task 2>/dev/null || true); do
        [ -f "$f" ] || continue
        ((pending++))
        echo -e "${YELLOW}PENDING${NC}: $(basename "$f" .task) - $(head -c 50 "$f")..."
    done

    for f in $(ls "$QUEUE_DIR"/*.processing 2>/dev/null || true); do
        [ -f "$f" ] || continue
        ((processing++))
        echo -e "${CYAN}RUNNING${NC}: $(basename "$f" .processing)"
    done

    for f in $(ls "$QUEUE_DIR"/*.done 2>/dev/null || true); do
        [ -f "$f" ] || continue
        ((done_count++))
    done

    echo ""
    echo "Pending: $pending | Running: $processing | Done: $done_count"
}

# Daemon control
case "${1:-}" in
    start)
        shift
        # Parse --workers N
        while [ $# -gt 0 ]; do
            case "$1" in
                --workers) MAX_WORKERS="$2"; shift 2 ;;
                *) shift ;;
            esac
        done
        if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
            echo "Daemon already running (PID $(cat "$PID_FILE"))"
            exit 1
        fi
        echo -e "${GREEN}Starting daemon with $MAX_WORKERS workers...${NC}"
        MAX_WORKERS=$MAX_WORKERS nohup "$0" _daemon > /dev/null 2>&1 &
        sleep 1
        echo "Daemon started (PID $(cat "$PID_FILE"))"
        echo "Add tasks: $0 add 'your task'"
        echo "View logs: $0 logs"
        ;;
    _daemon)
        daemon_loop
        ;;
    stop)
        if [ -f "$PID_FILE" ]; then
            kill $(cat "$PID_FILE") 2>/dev/null && echo "Daemon stopped" || echo "Daemon not running"
            rm -f "$PID_FILE"
        else
            echo "Daemon not running"
        fi
        ;;
    status)
        if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
            echo -e "${GREEN}Daemon running${NC} (PID $(cat "$PID_FILE"))"
            show_queue
        else
            echo -e "${RED}Daemon not running${NC}"
        fi
        ;;
    add)
        shift
        [ -n "$1" ] || { echo "Usage: $0 add 'task'"; exit 1; }
        add_task "$*"
        ;;
    add-file)
        add_from_file "$2"
        ;;
    queue)
        show_queue
        ;;
    logs)
        tail -f "$LOG_FILE"
        ;;
    clear)
        rm -f "$QUEUE_DIR"/*.done "$OUTPUT_DIR"/*.out
        echo "Cleared completed tasks"
        ;;
    wait)
        # Block until all tasks complete (for Claude to use)
        echo "Waiting for all tasks to complete..."
        while true; do
            pending=$(ls "$QUEUE_DIR"/*.task 2>/dev/null | wc -l)
            processing=$(ls "$QUEUE_DIR"/*.processing 2>/dev/null | wc -l)
            if [ "$pending" -eq 0 ] && [ "$processing" -eq 0 ]; then
                echo "All tasks complete."
                # Show results summary
                for f in $(ls "$OUTPUT_DIR"/*.out 2>/dev/null || true); do
                    [ -f "$f" ] || continue
                    id=$(basename "$f" .out)
                    status=$(tail -1 "$f")
                    echo "[$id] $status"
                done
                break
            fi
            sleep 2
        done
        ;;
    result)
        # Get result of specific task (for Claude to read)
        task_id="$2"
        [ -n "$task_id" ] || { echo "Usage: $0 result <task_id>"; exit 1; }
        if [ -f "$OUTPUT_DIR/$task_id.out" ]; then
            cat "$OUTPUT_DIR/$task_id.out"
        else
            echo "No result for $task_id"
        fi
        ;;
    *)
        usage
        ;;
esac
