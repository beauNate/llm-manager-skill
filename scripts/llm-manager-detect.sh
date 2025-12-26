#!/bin/bash
# LLM Manager Auto-Detection Hook
# Detects if task should be delegated to external LLMs

PROMPT="$CLAUDE_USER_PROMPT"
PROMPT_LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

# Delegation trigger patterns
DELEGATE_PATTERNS="implement|create|build|write code|fix bug|add feature|refactor|generate|scaffold|make a|code this|write a function|write a script|develop"

# Check if prompt matches delegation patterns
if echo "$PROMPT_LOWER" | grep -qiE "$DELEGATE_PATTERNS"; then
    # Check if any backend is available
    AVAILABLE=""
    command -v gemini >/dev/null 2>&1 && AVAILABLE="$AVAILABLE gemini"
    command -v codex >/dev/null 2>&1 && AVAILABLE="$AVAILABLE codex"
    command -v qwen >/dev/null 2>&1 && AVAILABLE="$AVAILABLE qwen"

    if [ -n "$AVAILABLE" ]; then
        echo "💡 LLM Manager: Delegation opportunity detected. Available agents:$AVAILABLE"
        echo "   Use: ~/.claude/skills/llm-manager/scripts/llm-task.sh \"task\""
    fi
fi

exit 0
