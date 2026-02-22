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
cd /c/anbs-dev/agentic-engineering && git add -A && git commit && git push
```

**If a hard link breaks** (tool deleted and recreated the file instead of editing in place), re-create it:
```powershell
New-Item -ItemType HardLink -Path 'C:\Users\nanbu\.claude\commands\<file>.md' -Target 'C:\anbs-dev\agentic-engineering\skills\<file>.md'
New-Item -ItemType HardLink -Path 'C:\Users\nanbu\.claude\agents\<file>.md' -Target 'C:\anbs-dev\agentic-engineering\agents\<file>.md'
```

## Key Patterns

- **Counter-review**: Agent assigns dispositions (agree/partial/defer/reject) to every finding before acting
- **Decision gate**: User breaks ties on reject AND defer — nothing silently ignored
- **Convergence loop**: Min 2 rounds (review + re-review), max 5. Exits when all MUST FIX resolved and fixes verified

## Skill Design Rules

- Codex model inherited from `~/.codex/config.toml` — never hardcode `-m`
- Do NOT use `-a` flag with `codex exec` — it's not supported on the exec subcommand (approvals default to never in non-interactive mode)
- Use codex `-C <dir>` instead of `cd` to avoid compound command approval prompts
- Use Read/Write tools for file operations — never `cp`, `mv`, or shell redirects
- Generate session IDs natively — no Bash calls for setup
- All temp files go in `.review/` inside the project root (gitignored) — avoids permission prompts and is cross-platform

## Origin

Grew out of [Paira](https://github.com/anbuneel/paira). The TypeScript CLI hit a nested Claude invocation blocker — skills sidestep it entirely since Claude IS the session.
