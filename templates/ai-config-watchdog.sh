#!/bin/bash
# AI config watchdog: ensures security directives are present in ALL AI tool config files
# Runs periodically via LaunchAgent — re-locks files if tampered/overwritten
# If an AI CLI installer overwrites our config, this script restores + re-locks it

MARKER="System Security Directives"
TEMPLATE="$HOME/.ssh/.ai-system-instructions.md"

# Files that should be the template exactly (direct copy)
DIRECT_FILES=(
  "$HOME/.codex/AGENTS.md"
  "$HOME/.gemini/GEMINI.md"
  "$HOME/.cursorrules"
  "$HOME/.windsurfrules"
  "$HOME/.github/copilot-instructions.md"
  "$HOME/AGENTS.md"
  "$HOME/INSTRUCTIONS.md"
)

# Files that should contain the template appended (check for marker)
APPEND_FILES=(
  "$HOME/.claude/CLAUDE.md"
)

[ ! -f "$TEMPLATE" ] && exit 0

FIXED=0

# Check direct-copy files
for f in "${DIRECT_FILES[@]}"; do
  if [ ! -f "$f" ] || ! grep -q "$MARKER" "$f" 2>/dev/null; then
    dir=$(dirname "$f")
    mkdir -p "$dir" 2>/dev/null
    sudo chflags noschg "$f" 2>/dev/null
    cp "$TEMPLATE" "$f"
    sudo chflags schg "$f" 2>/dev/null
    FIXED=$((FIXED+1))
  fi
done

# Check append files
for f in "${APPEND_FILES[@]}"; do
  if [ ! -f "$f" ] || ! grep -q "$MARKER" "$f" 2>/dev/null; then
    dir=$(dirname "$f")
    mkdir -p "$dir" 2>/dev/null
    sudo chflags noschg "$f" 2>/dev/null
    [ -f "$f" ] && echo "" >> "$f"
    cat "$TEMPLATE" >> "$f"
    sudo chflags schg "$f" 2>/dev/null
    FIXED=$((FIXED+1))
  fi
done

# Re-lock all (in case schg was removed)
for f in "${DIRECT_FILES[@]}" "${APPEND_FILES[@]}"; do
  sudo chflags schg "$f" 2>/dev/null
done

[ "$FIXED" -gt 0 ] && echo "$(date): restored $FIXED AI config files" >> /tmp/ai-watchdog.log
