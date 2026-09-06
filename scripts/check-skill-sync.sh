#!/usr/bin/env bash
# Check that installed skills and agents still match this repo.
# Runs on Claude Code session start via a SessionStart hook.
#
# Every install root this repo can target is checked, not just Claude Code's.
# A stale copy in one runtime while another stays current is invisible
# otherwise -- exactly how a months-old skill can sit in ~/.codex/skills while
# the Claude symlink reports clean.
#
# A root is only checked when it is in use: it exists and already holds at
# least one file from this repo. A machine that installs for one runtime is
# never nagged about the others.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_DIR="$REPO_DIR/skills"
AGENT_DIR="$REPO_DIR/agents"

[ -d "$SKILL_DIR" ] || exit 0

CODEX_SKILLS="${CODEX_HOME:-$HOME/.codex}/skills"

HAVE_GIT=0
if command -v git > /dev/null 2>&1 && git -C "$REPO_DIR" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  HAVE_GIT=1
fi

# Only tracked files are shipped skills. Without this, a work-in-progress
# skill sitting untracked in skills/ is reported as "missing" from every
# install root it was never meant to reach.
is_shipped() {
  [ "$HAVE_GIT" -eq 1 ] || return 0
  git -C "$REPO_DIR" ls-files --error-unmatch "$1" > /dev/null 2>&1
}

drifted=()

# check_root <label> <source-dir> <root-dir> <target-template>
# The template uses %NAME% for the source file's basename without .md.
check_root() {
  local label="$1"
  local src_dir="$2"
  local root="$3"
  local template="$4"
  local file name target in_use=0

  [ -d "$src_dir" ] || return 0
  [ -d "$root" ] || return 0

  for file in "$src_dir"/*.md; do
    [ -f "$file" ] || continue
    is_shipped "$file" || continue
    name="$(basename "$file" .md)"
    target="${template//%NAME%/$name}"
    if [ -f "$target" ]; then
      in_use=1
      break
    fi
  done
  [ "$in_use" -eq 1 ] || return 0

  for file in "$src_dir"/*.md; do
    [ -f "$file" ] || continue
    is_shipped "$file" || continue
    name="$(basename "$file" .md)"
    target="${template//%NAME%/$name}"
    if [ ! -f "$target" ]; then
      drifted+=("$label: $name (missing)")
    elif ! diff -q "$file" "$target" > /dev/null 2>&1; then
      drifted+=("$label: $name (differs)")
    fi
  done
}

check_root "claude"        "$SKILL_DIR" "$HOME/.claude/commands"   "$HOME/.claude/commands/%NAME%.md"
check_root "codex"         "$SKILL_DIR" "$CODEX_SKILLS"            "$CODEX_SKILLS/%NAME%/SKILL.md"
check_root "agents"        "$SKILL_DIR" "$HOME/.agents/skills"     "$HOME/.agents/skills/%NAME%/SKILL.md"
check_root "claude-agents" "$AGENT_DIR" "$HOME/.claude/agents"     "$HOME/.claude/agents/%NAME%.md"

if [ ${#drifted[@]} -gt 0 ]; then
  echo "SKILL SYNC DRIFT: ${#drifted[@]} file(s) out of sync with $REPO_DIR"
  for f in "${drifted[@]}"; do
    echo "  - $f"
  done
  echo "Fix: pwsh \"$SCRIPT_DIR/install-skill-links.ps1\" -Targets Claude,Codex"
fi
