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

Code review runs in rounds (max 5). Each round: collect agent feedback → counter-review → fix → push → repeat. Exits early when all critical findings are resolved.

## Install

### Claude Code

```bash
git clone https://github.com/anbuneel/agentic-engineering.git
# Skills → ~/.claude/commands/
cp agentic-engineering/skills/*.md ~/.claude/commands/
# Agents → ~/.claude/agents/
cp agentic-engineering/agents/*.md ~/.claude/agents/
```

Or install individually:

```bash
# Skills
curl -o ~/.claude/commands/peer-review-code.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/skills/peer-review-code.md
curl -o ~/.claude/commands/peer-review-plan.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/skills/peer-review-plan.md
curl -o ~/.claude/commands/merge.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/skills/merge.md

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

**GitHub Apps (optional, for multi-agent coverage):**
1. [Claude bot](https://github.com/apps/claude) — automatic PR review
2. [Devin](https://github.com/apps/devin-ai-integration) — automatic PR review
3. [OpenAI Codex](https://github.com/apps/openai-codex) — automatic PR review

All three are optional. The skill continues with local Codex CLI review if none respond.

### Peer Review Plan

- [Codex CLI](https://github.com/openai/codex) — `npm install -g @openai/codex`

### Merge & Document

- Git
- [GitHub CLI (`gh`)](https://cli.github.com/)

## Origin

These grew out of [Paira](https://github.com/anbuneel/paira), a multi-agent orchestration project for agentic engineering. The original TypeScript CLI approach hit a fundamental blocker (nested agent invocation), which led to the realization that markdown instruction files are simpler, more reliable, and agent-agnostic.

## License

MIT
