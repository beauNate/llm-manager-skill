# LLM Manager Skill

Multi-agent orchestration skill for Claude Code that delegates tasks to external LLM CLIs.

## Supported Agents

| Agent | Role | Command | Best For |
|-------|------|---------|----------|
| **Gemini** | Creative/Fast | `gemini --yolo` | Images, video, quick tasks |
| **Codex** | Senior | `codex exec -s danger-full-access` | Complex reasoning, debugging |
| **Qwen** | Research | `qwen --yolo` | Large context, thorough analysis |
| **Claude** | Architect | `claude -p --dangerously-skip-permissions` | Planning, orchestration |

## Installation

```bash
# Clone to Claude Code skills directory
git clone https://github.com/beauNate/llm-manager-skill.git ~/.claude/skills/llm-manager

# Make scripts executable
chmod +x ~/.claude/skills/llm-manager/scripts/*.sh

# (Optional) Add auto-detection hook to ~/.claude/settings.json
```

### Hook Setup (Optional)

Add to `~/.claude/settings.json` for automatic detection:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/skills/llm-manager/scripts/llm-manager-detect.sh",
            "timeout": 1000
          }
        ]
      }
    ]
  }
}
```

## Usage

### Single Task (llm-task.sh)

```bash
# Auto-route to best agent (runs in background by default)
llm-task.sh "Create a hello world script"

# Force foreground (wait for completion)
llm-task.sh -F "Quick task"

# Force specific backend
llm-task.sh -b gemini "Generate a logo"
llm-task.sh -b codex "Debug this function"
llm-task.sh -b qwen "Analyze entire codebase"
llm-task.sh -b claude "Plan the architecture"

# Brainstorm mode (all agents work on same task)
llm-task.sh --brainstorm "How should we architect this feature?"

# Swarm mode (multiple tasks in parallel)
llm-task.sh --swarm "task1" "task2" "task3"

# Collect brainstorm results
llm-task.sh --collect
llm-task.sh --collect --md  # Save to markdown

# Check status / clear
llm-task.sh --status
llm-task.sh --clear
```

### Daemon Mode (llm-daemon.sh)

For autonomous, long-running task processing:

```bash
# Start daemon (unlimited parallel workers)
llm-daemon.sh start
llm-daemon.sh start --workers 8  # Limit workers

# Queue tasks
llm-daemon.sh add "Implement feature X"
llm-daemon.sh add-file tasks.txt  # One task per line

# Monitor
llm-daemon.sh queue    # Show queue status
llm-daemon.sh logs     # Tail logs
llm-daemon.sh wait     # Block until all complete

# Get results
llm-daemon.sh result <task_id>

# Stop
llm-daemon.sh stop
```

## Smart Routing

Tasks are automatically routed based on keywords:

| Keywords | Routes To |
|----------|-----------|
| quick, fast, simple, image, video | Gemini (Creative/Fast) |
| debug, refactor, review, complex | Codex (Senior) |
| thorough, comprehensive, codebase, large | Qwen (Research) |
| plan, orchestrate, strategy, design | Claude (Architect) |

## Features

- **Smart Routing**: Keywords auto-route to best agent
- **Brainstorm Mode**: All agents work on same problem
- **Swarm Mode**: Multiple tasks in parallel
- **Parallel Execution**: Unlimited concurrent tasks
- **Auto-retry + Failover**: 3 retries, then try other backends
- **Background by Default**: All tasks run async
- **Markdown Export**: Save brainstorm results
- **macOS Notifications**: Alerts on complete/fail
- **Daemon Mode**: Autonomous queue processing

## Requirements

At least one of:
- [Gemini CLI](https://github.com/google-gemini/gemini-cli)
- [OpenAI Codex CLI](https://github.com/openai/codex)
- [Qwen Code CLI](https://www.npmjs.com/package/@anthropic-ai/claude-code)
- [Claude Code CLI](https://www.npmjs.com/package/@anthropic-ai/claude-code)

## License

MIT
