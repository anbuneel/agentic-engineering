# CLAUDE.md

## Project Overview

Agentic Engineering — a collection of workflow skills and sub-agents for AI coding agents. Published at https://github.com/anbuneel/agentic-engineering.

## Structure

```
skills/          ← User-invoked workflows (/command-name)
  peer-review-code.md
  peer-review-plan.md
  merge.md
agents/          ← Sub-agents (invoked via Task tool)
  codebase-snapshot.md
  code-cleanup-analyst.md
  code-simplifier.md
```

## Hard Links

`~/.claude/commands/` and `~/.claude/agents/` files are hard-linked to this repo's `skills/` and `agents/` folders. Edit in either location, changes sync instantly.

**To publish changes:**
```bash
cd /c/anbs-dev/agentic-engg-skills && git add -A && git commit && git push
```

**If a hard link breaks** (tool deleted and recreated the file instead of editing in place), re-create it:
```powershell
New-Item -ItemType HardLink -Path 'C:\Users\nanbu\.claude\commands\<file>.md' -Target 'C:\anbs-dev\agentic-engg-skills\skills\<file>.md'
New-Item -ItemType HardLink -Path 'C:\Users\nanbu\.claude\agents\<file>.md' -Target 'C:\anbs-dev\agentic-engg-skills\agents\<file>.md'
```

## Key Patterns

- **Counter-review**: Agent assigns dispositions (agree/partial/defer/reject) to every finding before acting
- **Decision gate**: User breaks ties on reject AND defer — nothing silently ignored
- **Convergence loop**: Code review runs max 5 rounds, exits early when all MUST FIX resolved

## Origin

Grew out of [Paira](https://github.com/anbuneel/paira). The TypeScript CLI hit a nested Claude invocation blocker — skills sidestep it entirely since Claude IS the session.
