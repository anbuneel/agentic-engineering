# Agentic Engineering Skills

Workflow skills for AI coding agents. Each skill is a markdown instruction file that any AI agent can follow to execute a structured development workflow.

Built for [Claude Code](https://claude.ai/code) but the workflow logic (counter-review, decision gates, convergence loops) is agent-agnostic.

## Skills

| Skill | File | Description |
|-------|------|-------------|
| **Peer Review Code** | [`peer-review-code.md`](peer-review-code.md) | Multi-agent code review with counter-review, automated fixes, and convergence loop |
| **Peer Review Plan** | [`peer-review-plan.md`](peer-review-plan.md) | Iterative plan review between your agent and Codex CLI with counter-review and decision gate |
| **Merge & Document** | [`merge.md`](merge.md) | Squash-merge a PR and update all project documentation |

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

Copy the skill files to your commands directory:

```bash
# All skills
git clone https://github.com/anbuneel/agentic-engg-skills.git
cp agentic-engg-skills/*.md ~/.claude/commands/

# Or individual skills
curl -o ~/.claude/commands/peer-review-code.md https://raw.githubusercontent.com/anbuneel/agentic-engg-skills/main/peer-review-code.md
curl -o ~/.claude/commands/peer-review-plan.md https://raw.githubusercontent.com/anbuneel/agentic-engg-skills/main/peer-review-plan.md
curl -o ~/.claude/commands/merge.md https://raw.githubusercontent.com/anbuneel/agentic-engg-skills/main/merge.md
```

Then invoke with `/peer-review-code`, `/peer-review-plan`, or `/merge` in Claude Code.

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

These skills grew out of [Paira](https://github.com/anbuneel/paira), a multi-agent orchestration project for agentic engineering. The original TypeScript CLI approach hit a fundamental blocker (nested agent invocation), which led to the realization that markdown instruction files are simpler, more reliable, and agent-agnostic.

## License

MIT
