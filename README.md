# Agentic Engineering

Slash commands for [Claude Code](https://claude.ai/code) that add multi-agent code review, security scanning, and automated documentation workflows. Type `/peer-review-code` and your PR gets reviewed by multiple AI agents, counter-reviewed, and fixed — automatically.

Each skill is a markdown file. Drop it in `~/.claude/commands/`, and it becomes a slash command. No build step, no package manager — just files.

## Who Is This For?

You use Claude Code and want structured, repeatable workflows — not ad-hoc prompting. Install a skill, run it with `/command-name`, and the agent handles the rest.

**You'll need:**
- [Claude Code](https://claude.ai/code) (primary target) — skills work as slash commands out of the box
- Git and a GitHub repo for most workflows

**Optional:** [Codex CLI](https://github.com/openai/codex) (`npm install -g @openai/codex`) — OpenAI's command-line coding agent. The peer-review skills use it as a **second reviewer from a different model**, so you get an independent perspective instead of Claude reviewing its own work. Without Codex, those two skills won't run, but the other four work fine on their own.

| Skill | Needs Codex? |
|-------|-------------|
| `/security-posture` | No |
| `/security-scan` | No |
| `/security-audit` | No (optional second opinion) |
| `/merge` | No |
| `/peer-review-code` | Yes |
| `/peer-review-plan` | Yes |

**Status:** Active development. Used daily by the author on real projects. Core skills (peer review, security) are stable. Expect new skills and refinements regularly.

## Why This Exists

AI coding assistants are powerful, but ad-hoc prompting doesn't scale. You end up repeating the same review instructions, forgetting edge cases, and getting inconsistent results across sessions. These skills codify workflows that I run daily — turning them into repeatable, debuggable processes.

The key insight: **prompts deserve the same rigor as code.** These markdown files have error handling, state management, convergence criteria, and rollback logic — not because it's over-engineering, but because without it, multi-agent workflows silently fail in ways you don't notice until production.

The counter-review pattern came from a specific frustration: AI agents blindly apply every piece of feedback they receive, even when it's wrong. Having Claude assign dispositions (agree/partial/defer/reject) to each finding — and requiring the human to break ties on rejections — means nothing is silently applied and nothing is silently ignored.

Why markdown instead of code? An earlier attempt as a TypeScript CLI hit a fundamental blocker: you can't easily nest one AI agent session inside another. Markdown instruction files sidestep that entirely — the agent *is* the runtime, and the skill is just a set of instructions it follows. No build step, no dependency management, no version conflicts.

## Skills

### `/peer-review-code` — Multi-Agent Code Review

[`skills/peer-review-code.md`](skills/peer-review-code.md) | Requires: git, gh, Codex CLI

Claude reviews your PR, sends it to Codex CLI and GitHub bots for independent second opinions, then **counter-reviews every finding** — agreeing, scoping down, deferring, or rejecting with justification. You break ties on rejections. Runs 2-5 rounds until all issues are resolved, with a mandatory verification round after fixes.

See a [sample review artifact](docs/examples/code-review-sample.md) to understand what the output looks like.

**What makes it different:** Most AI review tools apply all feedback blindly. This one fights back — Claude critically evaluates each suggestion before acting, and nothing is silently applied or silently ignored.

### `/peer-review-plan` — Two-Agent Plan Review

[`skills/peer-review-plan.md`](skills/peer-review-plan.md) | Requires: Codex CLI

Claude and Codex CLI take turns reviewing a plan document. Each round: Codex reviews → Claude counter-reviews with dispositions → you resolve disputes → Claude revises → repeat. Min 2 rounds, max 5.

**What makes it different:** Gets a second model's perspective on your architecture before you write any code.

### `/security-posture` — Security Hygiene Scorecard

[`skills/security-posture.md`](skills/security-posture.md) | Requires: git. Optional: gh

Checks 16 security hygiene items across 6 categories: secrets management, dependency security, code quality gates, access control, container security, and infrastructure. Returns a letter-graded scorecard (A-F) with specific fix recommendations.

**What makes it different:** No scanning tools needed — it checks your project's *infrastructure and configuration*, not your code. Zero setup, instant results.

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
│  • Enable branch protection on default branch       │
└─────────────────────────────────────────────────────┘
```

### `/security-scan` — SAST, Dependencies, and Secrets

[`skills/security-scan.md`](skills/security-scan.md) | Requires: git + at least one of Semgrep, Gitleaks, or npm

Runs Semgrep (static analysis), `npm audit` (dependency vulnerabilities), and Gitleaks (secret detection) across your codebase. Auto-detects which tools are installed and runs only those. Outputs a consolidated report with findings by severity.

**What makes it different:** Orchestrates multiple scanning tools in one command and merges the results. Missing tools are reported with install instructions, not silent failures.

### `/security-audit` — AI-Driven Security Review

[`skills/security-audit.md`](skills/security-audit.md) | Requires: git. Optional: Codex CLI

Deep security review using Claude + specialized agents to analyze your codebase for vulnerabilities. Codex CLI adds an independent AI assessment if installed. All findings go through counter-review before action — same disposition system as peer review.

**What makes it different:** Combines multiple AI agents looking at your code from different security angles, then critically evaluates their findings instead of dumping a raw list.

### `/merge` — Squash-Merge with Auto-Documentation

[`skills/merge.md`](skills/merge.md) | Requires: git, gh

Squash-merges the current PR, switches to the target branch, then auto-updates README, CHANGELOG, and CLAUDE.md to reflect the completed work. Includes preflight checks (clean tree, PR state, merge conflicts) and safe branch cleanup.

**What makes it different:** The doc update step is the point — it ensures your project documentation stays in sync with merged work instead of drifting.

## Agents

Background sub-agents invoked via the Task tool. These run alongside your work, not as slash commands.

### Codebase Snapshot

[`agents/codebase-snapshot.md`](agents/codebase-snapshot.md)

Captures a point-in-time snapshot of your codebase: architecture diagram, tech stack, file/line metrics, deployment info, and a timeline of changes since the last snapshot. Useful for documenting progress between milestones.

### Code Cleanup Analyst

[`agents/code-cleanup-analyst.md`](agents/code-cleanup-analyst.md)

Scans for dead code, unused imports, deprecated functions, and redundant files. Reports findings with confidence levels and safety notes so you can remove code without breaking things.

### Code Simplifier

[`agents/code-simplifier.md`](agents/code-simplifier.md)

Reviews recently modified code and simplifies it for clarity and consistency — flattening unnecessary nesting, removing redundant logic, and aligning with project conventions. Runs automatically as the first step of `/peer-review-code`.

## Key Patterns

These patterns are shared across the review skills.

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
curl -o ~/.claude/commands/security-audit.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/skills/security-audit.md
curl -o ~/.claude/commands/security-posture.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/skills/security-posture.md

# Agents
curl --create-dirs -o ~/.claude/agents/codebase-snapshot.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/agents/codebase-snapshot.md
curl --create-dirs -o ~/.claude/agents/code-cleanup-analyst.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/agents/code-cleanup-analyst.md
curl --create-dirs -o ~/.claude/agents/code-simplifier.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/agents/code-simplifier.md
```

### Using with Other AI Tools

These are markdown files — any AI agent that can read instructions and execute shell commands can use them. Adapt the tool-specific references (Edit, Write, Task, Bash) to your agent's tool names.

**Verify your installation:** Run `/security-posture` in any git repo. If you see a scorecard, you're set.

## Tool Setup

**Required for all skills:**
- [Claude Code](https://claude.ai/code)
- Git

**Per-skill dependencies:**

| Tool | Install | Used by |
|------|---------|---------|
| [GitHub CLI (`gh`)](https://cli.github.com/) | `brew install gh` then `gh auth login` | `/peer-review-code`, `/merge`, `/security-posture` (optional) |
| [Codex CLI](https://github.com/openai/codex) | `npm install -g @openai/codex` | `/peer-review-code`, `/peer-review-plan`, `/security-audit` (optional) |
| [Semgrep](https://semgrep.dev/) | `pip install semgrep` | `/security-scan` (optional) |
| [Gitleaks](https://github.com/gitleaks/gitleaks) | `brew install gitleaks` | `/security-scan` (optional) |

**Codex configuration:** Model and reasoning effort are inherited from `~/.codex/config.toml` — the skills do not hardcode a model:

```toml
model = "your-preferred-model"
model_reasoning_effort = "high"
```

**GitHub Apps (optional):** Install [Claude bot](https://github.com/apps/claude), [Devin](https://github.com/apps/devin-ai-integration), or [OpenAI Codex](https://github.com/apps/openai-codex) on your repo for additional automated PR review coverage. All optional — `/peer-review-code` works with just local Codex CLI.

## Cross-Platform

Skills work on Windows, macOS, and Linux:
- Temp files stored in `.review/` inside the project root — avoids permission prompts. The skill auto-creates this directory and adds it to `.gitignore` on first run
- Session IDs generated natively — no shell dependencies
- File operations use Read/Write tools instead of shell commands
- Codex working directory set via `-C` flag instead of `cd` to avoid compound command approval

## License

[MIT](LICENSE)
