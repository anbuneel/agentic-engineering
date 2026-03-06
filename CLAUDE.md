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
scripts/         ← Dev tooling
  check-skill-sync.sh
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

**Sync check:** Add a `SessionStart` hook to `~/.claude/settings.json` to detect drift at the start of every Claude Code session:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"<path-to-repo>/scripts/check-skill-sync.sh\"",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

## Key Patterns

- **Counter-review**: Agent assigns dispositions (agree/partial/defer/reject) to every finding before acting
- **Decision gate**: User breaks ties on reject AND defer — nothing silently ignored
- **Convergence loop**: Min 2 rounds (review + re-review), max 5. Exits when all MUST FIX resolved, fixes verified, and all GH bot findings confirmed resolved via cross-round fingerprint tracking

## Documentation Rules

- When modifying skill files (`skills/*.md`), always check and update `docs/SKILLS_GUIDE.md` and `README.md` if the change affects documented behavior, flow diagrams, or step naming

## Skill Design Rules

- Codex model inherited from `~/.codex/config.toml` — never hardcode `-m`
- Do NOT use `-a` flag with `codex exec` — it's not supported on the exec subcommand (approvals default to never in non-interactive mode)
- Use codex `-C <dir>` instead of `cd` to avoid compound command approval prompts
- Gemini model inherited from `~/.gemini/settings.json` (`general.model`) — never hardcode `-m`
- Gemini CLI: use `-p "prompt"` for non-interactive mode, `-y` for auto-approve
- Gemini CLI: capture output from Bash tool result and save with Write tool — do NOT use shell redirects (`>`) as they trigger approval prompts
- Gemini CLI: `--approval-mode plan` requires experimental flag — use `-y` with explicit "do NOT modify files" in prompt instead
- Use Read/Write tools for file operations — never `cp`, `mv`, or shell redirects
- Codex CLI: use `--json` flag for structured JSONL output when session ID capture is needed — parse `thread_id` from the first line (`{"type":"thread.started","thread_id":"<UUID>"}`)
- Generate session IDs natively — no Bash calls for setup
- All temp files go in `.review/` inside the project root (gitignored) — avoids permission prompts and is cross-platform

