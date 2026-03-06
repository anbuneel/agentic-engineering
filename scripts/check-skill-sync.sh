#!/usr/bin/env bash
# Check if agentic-engineering skills are synced with ~/.claude/commands
# Runs on Claude Code session start via project hook

SCRIPT_DIR="$(dirname "$0")"
REPO_DIR="$SCRIPT_DIR/../skills"
CMD_DIR="$HOME/.claude/commands"

drifted=()

for file in "$REPO_DIR"/*.md; do
  [ -f "$file" ] || continue
  name=$(basename "$file")
  target="$CMD_DIR/$name"
  if [ ! -f "$target" ]; then
    drifted+=("$name (missing)")
  elif ! diff -q "$file" "$target" > /dev/null 2>&1; then
    drifted+=("$name (differs)")
  fi
done

if [ ${#drifted[@]} -gt 0 ]; then
  echo "SKILL SYNC DRIFT: ${#drifted[@]} file(s) out of sync between skills/ repo and ~/.claude/commands/"
  for f in "${drifted[@]}"; do
    echo "  - $f"
  done
  echo "Fix: re-run hard link setup from CLAUDE.md"
fi
