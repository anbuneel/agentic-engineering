# Agentic Engineering

Workflow skills and sub-agents for AI coding agents. Each is a markdown instruction file that any AI agent can follow.

Built for [Claude Code](https://claude.ai/code) but the workflow logic is agent-agnostic.

## Skills

User-invoked workflows — run with `/command-name`.

| Skill | File | Description |
|-------|------|-------------|
| **Peer Review Code** | [`skills/peer-review-code.md`](skills/peer-review-code.md) | Multi-agent code review with counter-review, automated fixes, and convergence loop |
| **Peer Review Plan** | [`skills/peer-review-plan.md`](skills/peer-review-plan.md) | Iterative plan review between your agent and Codex CLI with counter-review and decision gate |
| **Merge & Document** | [`skills/merge.md`](skills/merge.md) | Squash-merge a PR and update all project documentation |
| **Security Scan** | [`skills/security-scan.md`](skills/security-scan.md) | Run SAST, dependency audit, and secret detection across the codebase |

## Agents

Sub-agents that run in the background via the Task tool.

| Agent | File | Description |
|-------|------|-------------|
| **Codebase Snapshot** | [`agents/codebase-snapshot.md`](agents/codebase-snapshot.md) | Capture point-in-time snapshot of codebase state — architecture, tech stack, metrics, timeline |
| **Code Cleanup Analyst** | [`agents/code-cleanup-analyst.md`](agents/code-cleanup-analyst.md) | Identify dead code, unused imports, deprecated functions, and redundant files for safe removal |
| **Code Simplifier** | [`agents/code-simplifier.md`](agents/code-simplifier.md) | Simplify and refine code for clarity, consistency, and maintainability |

## Key Patterns

### Counter-Review

The agent doesn't blindly apply reviewer feedback. Every finding gets a disposition:

| Disposition | Meaning | Action |
|-------------|---------|--------|
| **agree** | Reviewer is right | Fix / revise now |
| **partial** | Valid but scoped down | Fix the core issue |
| **defer** | Valid but not now | Log for later |
| **reject** | Disagree with reviewer | Must justify why |

### Decision Gate

When the agent rejects or defers a finding, **you break the tie**. No feedback is silently ignored.

### Convergence Loop

Code review runs in rounds (min 2, max 5). Each round: collect agent feedback → counter-review → fix → push → repeat. Requires at least one re-review round to verify fixes before converging.

## Install

### Quick Install (macOS / Linux)

```bash
git clone https://github.com/anbuneel/agentic-engineering.git
mkdir -p ~/.claude/commands ~/.claude/agents
cp agentic-engineering/skills/*.md ~/.claude/commands/
cp agentic-engineering/agents/*.md ~/.claude/agents/
```

**Want auto-sync?** Use hard links so edits in either location stay in sync:

```bash
git clone https://github.com/anbuneel/agentic-engineering.git
mkdir -p ~/.claude/commands ~/.claude/agents
ln agentic-engineering/skills/*.md ~/.claude/commands/
ln agentic-engineering/agents/*.md ~/.claude/agents/
```

### Quick Install (Windows)

```powershell
git clone https://github.com/anbuneel/agentic-engineering.git
Copy-Item agentic-engineering\skills\*.md ~\.claude\commands\
Copy-Item agentic-engineering\agents\*.md ~\.claude\agents\
```

**Want auto-sync?** Use hard links:

```powershell
git clone https://github.com/anbuneel/agentic-engineering.git
Get-ChildItem agentic-engineering\skills\*.md | ForEach-Object { New-Item -ItemType HardLink -Path "~\.claude\commands\$($_.Name)" -Target $_.FullName }
Get-ChildItem agentic-engineering\agents\*.md | ForEach-Object { New-Item -ItemType HardLink -Path "~\.claude\agents\$($_.Name)" -Target $_.FullName }
```

### Install Individual Files

```bash
# Skills
curl -o ~/.claude/commands/peer-review-code.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/skills/peer-review-code.md
curl -o ~/.claude/commands/peer-review-plan.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/skills/peer-review-plan.md
curl -o ~/.claude/commands/merge.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/skills/merge.md
curl -o ~/.claude/commands/security-scan.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/skills/security-scan.md

# Agents
curl --create-dirs -o ~/.claude/agents/codebase-snapshot.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/agents/codebase-snapshot.md
curl --create-dirs -o ~/.claude/agents/code-cleanup-analyst.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/agents/code-cleanup-analyst.md
curl --create-dirs -o ~/.claude/agents/code-simplifier.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/agents/code-simplifier.md
```

### Other Agents

These are markdown files — any AI agent that can read instructions and execute shell commands can use them. Adapt the tool-specific references (Edit, Write, Task, Bash) to your agent's tool names.

## Prerequisites

### Peer Review Code

**Local tools:**
- Git
- [GitHub CLI (`gh`)](https://cli.github.com/) — authenticated (`gh auth login`)
- [Codex CLI](https://github.com/openai/codex) — `npm install -g @openai/codex`

**Codex configuration:** Model and reasoning effort are inherited from `~/.codex/config.toml` — the skills do not hardcode a model. Configure your preferred model there:

```toml
model = "gpt-5.3-codex"
model_reasoning_effort = "xhigh"
```

**GitHub Apps (optional, for multi-agent coverage):**
1. [Claude bot](https://github.com/apps/claude) — automatic PR review
2. [Devin](https://github.com/apps/devin-ai-integration) — automatic PR review
3. [OpenAI Codex](https://github.com/apps/openai-codex) — automatic PR review

All three are optional. The skill continues with local Codex CLI review if none respond.

### Peer Review Plan

- [Codex CLI](https://github.com/openai/codex) — `npm install -g @openai/codex`

### Security Scan

**Required:**
- Git

**Scanning tools (at least one required):**
- [Semgrep](https://semgrep.dev/) — SAST scanner (`pip install semgrep` or `brew install semgrep`)
- [Gitleaks](https://github.com/gitleaks/gitleaks) — secret detection (`brew install gitleaks` or [download from releases](https://github.com/gitleaks/gitleaks/releases))
- npm (for `npm audit`) — runs automatically if `package.json` exists in the project root

The skill detects which tools are available and runs only those. Missing tools are reported with install instructions.

### Merge & Document

- Git
- [GitHub CLI (`gh`)](https://cli.github.com/)

## Cross-Platform

Skills work on Windows, macOS, and Linux:
- Temp files stored in `.review/` inside the project root — avoids permission prompts. The skill auto-creates this directory and adds it to `.gitignore` on first run
- Session IDs generated natively — no shell dependencies
- File operations use Read/Write tools instead of shell commands
- Codex working directory set via `-C` flag instead of `cd` to avoid compound command approval

## Origin

These grew out of [Paira](https://github.com/anbuneel/paira), a multi-agent orchestration project for agentic engineering. The original TypeScript CLI approach hit a fundamental blocker (nested agent invocation), which led to the realization that markdown instruction files are simpler, more reliable, and agent-agnostic.

## License

MIT
