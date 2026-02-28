# Agentic Engineering

Workflow skills and sub-agents for AI coding agents. Each is a markdown instruction file that any AI agent can follow.

Built for [Claude Code](https://claude.ai/code) but the workflow logic is agent-agnostic.

## Who Is This For?

You're an engineer using AI coding assistants (Claude Code, Codex CLI, or similar) and you want structured workflows for things like code review, security scanning, and documentation — not just ad-hoc prompting.

These skills and agents are **markdown instruction files**. They're not a CLI tool or a library — they're prompts that tell your AI agent *how* to run a multi-step workflow. Install them, invoke them with a slash command, and the agent handles the rest.

**You'll need:**
- [Claude Code](https://claude.ai/code) (primary target) — skills work as slash commands out of the box
- Git and a GitHub repo for most workflows
- [Codex CLI](https://github.com/openai/codex) (optional) — enables multi-agent review where Codex provides a second opinion

**Status:** Active development. Used daily by the author on real projects. Core skills (peer review, security) are stable. Expect new skills and refinements regularly.

## Skills

User-invoked workflows — run with `/command-name`.

| Skill | File | Description |
|-------|------|-------------|
| **Peer Review Code** | [`skills/peer-review-code.md`](skills/peer-review-code.md) | Multi-agent code review: Claude reviews your PR, sends it to Codex CLI and GitHub bots for second opinions, counter-reviews every finding, fixes what it agrees with, and asks you to break ties. Runs 2–5 rounds until converged. |
| **Peer Review Plan** | [`skills/peer-review-plan.md`](skills/peer-review-plan.md) | Two-agent plan review: Claude and Codex CLI take turns reviewing a plan document, with counter-review dispositions and a decision gate so nothing is silently ignored. |
| **Merge & Document** | [`skills/merge.md`](skills/merge.md) | Squash-merge a PR via `gh`, then auto-update README, CHANGELOG, and CLAUDE.md to reflect the completed work. Includes preflight checks and safe branch cleanup. |
| **Security Scan** | [`skills/security-scan.md`](skills/security-scan.md) | Run Semgrep (SAST), `npm audit` (dependencies), and Gitleaks (secrets) across your codebase. Auto-detects which tools are installed and runs only those. Outputs a consolidated report. |
| **Security Audit** | [`skills/security-audit.md`](skills/security-audit.md) | Deep AI-driven security review: Claude + specialized agents analyze your codebase for vulnerabilities, then Codex CLI provides an independent assessment. Findings go through counter-review before action. |
| **Security Posture** | [`skills/security-posture.md`](skills/security-posture.md) | Checks 16 security hygiene items across 6 categories (secrets, dependencies, code quality, access control, containers, infrastructure). Returns a letter-graded scorecard with specific recommendations. |

## Agents

Sub-agents that run in the background via the Task tool.

| Agent | File | Description |
|-------|------|-------------|
| **Codebase Snapshot** | [`agents/codebase-snapshot.md`](agents/codebase-snapshot.md) | Captures a point-in-time snapshot of your codebase: architecture diagram, tech stack, file/line metrics, deployment info, and a timeline of changes since the last snapshot. Useful for documenting progress between milestones. |
| **Code Cleanup Analyst** | [`agents/code-cleanup-analyst.md`](agents/code-cleanup-analyst.md) | Scans for dead code, unused imports, deprecated functions, and redundant files. Reports findings with confidence levels and safety notes so you can remove code without breaking things. |
| **Code Simplifier** | [`agents/code-simplifier.md`](agents/code-simplifier.md) | Reviews recently modified code and simplifies it for clarity and consistency — flattening unnecessary nesting, removing redundant logic, and aligning with project conventions. |

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

## Quick Start

Once installed, open Claude Code in any git repo and try:

```
/security-posture
```

No extra tools needed — it scans your project's security hygiene and returns a scorecard:

```
┌─────────────────────────────────────────────────────┐
│  Security Posture: B (75%)                          │
│                                                     │
│  1. Secrets Management        ██████████  3/3 PASS  │
│  2. Dependency Security       ██████░░░░  2/4 PASS  │
│  3. Code Quality Gates        ████████░░  2/3 PASS  │
│  4. Access Control            ██████░░░░  1/2 PASS  │
│  5. Container Security        ░░░░░░░░░░  N/A       │
│  6. Infrastructure            ████░░░░░░  1/3 PASS  │
│                                                     │
│  Top recommendations:                               │
│  • Add dependency pinning (lock file missing)       │
│  • Enable branch protection on main                 │
└─────────────────────────────────────────────────────┘
```

Then try the flagship skill — multi-agent code review on a feature branch:

```
/peer-review-code
```

This launches a full review cycle: Claude reviews your PR, sends it to Codex CLI for a second opinion, counter-reviews every finding, fixes what it agrees with, and asks you to break ties on anything it rejects. Runs 2–5 rounds until all issues are resolved.

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
curl -o ~/.claude/commands/security-audit.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/skills/security-audit.md
curl -o ~/.claude/commands/security-posture.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/skills/security-posture.md

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

### Security Audit

- Git
- [Codex CLI](https://github.com/openai/codex) (optional) — `npm install -g @openai/codex`

The skill uses Claude + pr-review-toolkit agents for AI analysis. Codex CLI adds an independent AI perspective if installed.

### Security Posture

- Git
- [GitHub CLI (`gh`)](https://cli.github.com/) (optional) — for branch protection checks

No external scanning tools needed — this checks project infrastructure and configuration only.

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

[MIT](LICENSE)
