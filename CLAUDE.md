# CLAUDE.md

## Project Overview

Agentic Engineering — a collection of workflow skills and sub-agents for AI coding agents. Published at https://github.com/anbuneel/agentic-engineering.

## Structure

```
skills/          ← User-invoked workflows (/command-name)
  peer-review-code.md
  peer-review-plan.md
  peer-ideate.md
  merge.md
  security-scan.md
  security-audit.md
  security-posture.md
agents/          ← Sub-agents (invoked via Task tool)
  codebase-snapshot.md
  code-cleanup-analyst.md
```

## Hard Links (Development Setup)

If you clone this repo and want edits to sync automatically with your Claude Code config, use hard links instead of copying:

```bash
# macOS / Linux
ln skills/*.md ~/.claude/commands/
ln agents/*.md ~/.claude/agents/
```

```powershell
# Windows
Get-ChildItem skills\*.md | ForEach-Object { New-Item -ItemType HardLink -Path "~\.claude\commands\$($_.Name)" -Target $_.FullName }
Get-ChildItem agents\*.md | ForEach-Object { New-Item -ItemType HardLink -Path "~\.claude\agents\$($_.Name)" -Target $_.FullName }
```

Edit in either location, changes sync instantly. If a hard link breaks (tool deleted and recreated the file instead of editing in place), re-run the commands above.

## Key Patterns

- **Counter-review**: Agent assigns dispositions (agree/partial/defer/reject) to every finding before acting
- **Decision gate**: User breaks ties on reject AND defer — nothing silently ignored
- **Convergence loop**: Min 2 rounds (review + re-review), max 5. Exits when all MUST FIX resolved and fixes verified

## Skill Design Rules

- Codex model inherited from `~/.codex/config.toml` — never hardcode `-m`
- Do NOT use `-a` flag with `codex exec` — it's not supported on the exec subcommand (approvals default to never in non-interactive mode)
- Use codex `-C <dir>` instead of `cd` to avoid compound command approval prompts
- Gemini model inherited from `~/.gemini/settings.json` (`general.model`) — never hardcode `-m`
- Gemini CLI: use `-p "prompt"` for non-interactive mode, `-y` for auto-approve, redirect stdout for output (`> file.md`)
- Gemini CLI: `--approval-mode plan` requires experimental flag — use `-y` with explicit "do NOT modify files" in prompt instead
- Use Read/Write tools for file operations — never `cp`, `mv`, or shell redirects
- Generate session IDs natively — no Bash calls for setup
- All temp files go in `.review/` inside the project root (gitignored) — avoids permission prompts and is cross-platform

