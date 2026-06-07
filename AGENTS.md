# AGENTS.md

## Project Overview

Agentic Engineering — a collection of agent-agnostic workflow skills and sub-agents for AI coding agents. Published at https://github.com/anbuneel/agentic-engineering.

## Structure

```
skills/          ← User-invoked workflows (/command-name)
  multi-agent-code-review.md
  multi-agent-plan-review.md
  multi-agent-ideate.md
  merge.md
  security-scan.md
  security-audit.md
  security-posture.md
agents/          ← Claude-compatible sub-agents; Codex equivalents are runtime prompts for now
  codebase-snapshot.md
  code-cleanup-analyst.md
tools/           ← Standalone CLI tools
  claude-memory-sync/  ← Cross-machine Claude memory sync via git
  codex-setup-sync/    ← Cross-machine Codex setup sync via git
scripts/         ← Dev tooling
  check-skill-sync.sh
```

## Live Links (Development Setup)

If you clone this repo and want edits to sync automatically with your local agent config, use links instead of copying.

Claude Code command/agent links:

```bash
# macOS / Linux
ln skills/*.md ~/.claude/commands/
ln agents/*.md ~/.claude/agents/
```

```powershell
# Windows
Get-ChildItem skills\*.md | ForEach-Object { New-Item -ItemType SymbolicLink -Path "~\.claude\commands\$($_.Name)" -Target $_.FullName }
Get-ChildItem agents\*.md | ForEach-Object { New-Item -ItemType SymbolicLink -Path "~\.claude\agents\$($_.Name)" -Target $_.FullName }
```

Windows hard links cannot cross drives. If the repo and agent config live on different drives, use symbolic links; symlink creation requires Developer Mode or an elevated shell.

Codex skills use a `SKILL.md` inside each skill directory under `$CODEX_HOME/skills` (usually `~/.codex/skills`). Some setups also load shared skills from `~/.agents/skills/`. This modernization pass keeps one canonical Markdown file per skill and documents Codex installation, but does not add generated Codex plugin packaging or install bundles.

Use `.\scripts\install-skill-links.ps1 -Targets Codex` to symlink shipped skills into Codex. Use `-Targets Agents` for `~/.agents/skills/`, or `-Targets Claude,Codex` to link both Claude Code and Codex. The script falls back to copies only when symlink creation is not permitted.

Edit in either location, changes sync instantly. If a link breaks (tool deleted and recreated the file instead of editing in place), re-run the commands above or the installer script.

**Claude sync check:** Add a `SessionStart` hook to `~/.claude/settings.json` to detect drift at the start of every Claude Code session:

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
- **Reviewer registry**: Multi-agent skills record primary driver, native subagents, external CLI reviewers, common GH review agents, skipped reviewers, and independence notes

## Documentation Rules

- When modifying skill files (`skills/*.md`), always check and update `docs/SKILLS_GUIDE.md` and `README.md` if the change affects documented behavior, flow diagrams, or step naming
- Only document tracked, shipped skills in README and SKILLS_GUIDE

## Skill Design Rules

- Codex model inherited from `~/.codex/config.toml` — never hardcode `-m`
- Claude reviewer channel should be included when Codex is the primary driver and the channel is configured: run `claude -p "<prompt>" --permission-mode plan --allowedTools "Read" "Grep" "Glob" ... --disallowedTools "Edit" "Write" "MultiEdit" --output-format json`, parse `session_id`, store it as `externalThreadIds.claude`, write `result` to `.review/`, and resume later rounds with `--resume`
- Launch Claude CLI reviewer commands with command cwd set to `PROJECT_ROOT`; Claude has no `-C`, so if cwd cannot be set directly, add `--add-dir "${PROJECT_ROOT}"` and include the repo root in the prompt
- GitHub review agents are common reviewer inputs for all primary drivers
- Same-model secondary sessions are skipped by default unless explicitly requested; if run, label them as secondary same-family review
- External reviewers are advisory by default; a reviewer is required only when explicitly requested by the user
- When Codex is primary, external reviewer subprocesses (`claude`, `gemini`, optional secondary `codex`) require sandbox/approval settings that permit launching those commands and using network-backed model sessions; policy-blocked advisory reviewers are skipped and recorded
- Do NOT use `-a` flag with `codex exec` — it's not supported on the exec subcommand (approvals default to never in non-interactive mode)
- Do NOT use `-s` or `-C` flags with `codex exec resume` — resume only accepts `[SESSION_ID]` and `[PROMPT]` (plus `--json`); sandbox and working directory are inherited from the original session
- Use codex `-C <dir>` instead of `cd` to avoid compound command approval prompts
- Gemini model inherited from `~/.gemini/settings.json` (`general.model`) — never hardcode `-m`
- Gemini CLI: use `-p "prompt"` for non-interactive mode, `-y` for auto-approve
- Gemini CLI: capture output from the shell result and save with the primary driver's file-write capability — do NOT use shell redirects (`>`) as they trigger approval prompts
- Gemini CLI: `--approval-mode plan` requires experimental flag — use `-y` with explicit "do NOT modify files" in prompt instead
- Use the primary driver's native file tools for file operations — never `cp`, `mv`, or shell redirects
- Codex CLI: use `--json` flag for structured JSONL output when session ID capture is needed — parse `thread_id` from the first line (`{"type":"thread.started","thread_id":"<UUID>"}`)
- Generate session IDs natively — no Bash calls for setup
- All temp files go in `.review/` inside the project root (gitignored) — avoids permission prompts and is cross-platform

