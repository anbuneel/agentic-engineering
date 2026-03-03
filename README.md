# Agentic Engineering

Slash commands for [Claude Code](https://claude.ai/code) that add multi-agent code review, security scanning, and automated documentation workflows. Type `/peer-review-code` and your PR gets reviewed by multiple AI agents, counter-reviewed, and fixed — automatically.

**👉 View the [Visual Skills Guide](docs/SKILLS_GUIDE-gemini.md) for a deep dive into the workflows.**

Each skill is a markdown file. Drop it in `~/.claude/commands/`, and it becomes a slash command. No build step, no package manager — just files.

## Who Is This For?

You use Claude Code and want structured, repeatable workflows — not ad-hoc prompting. Install a skill, run it with `/command-name`, and the agent handles the rest.

**You'll need:**
- [Claude Code](https://claude.ai/code) (primary target) — skills work as slash commands out of the box
- Git and a GitHub repo for most workflows

**Optional:** [Codex CLI](https://github.com/openai/codex) (`npm install -g @openai/codex`) and [Gemini CLI](https://github.com/google-gemini/gemini-cli) (`npm install -g @google/gemini-cli`) — used as independent model voices in multi-agent workflows. Without them, skills degrade gracefully (see table).

| Skill | Needs Codex? | Needs Gemini? |
|-------|-------------|---------------|
| `/peer-review-code` | Yes | No |
| `/peer-review-plan` | Yes | No |
| `/peer-ideate` | Optional | Optional |
| `/security-posture` | No | No |
| `/security-scan` | No | No |
| `/security-audit` | No (optional) | No |
| `/merge` | No | No |

**Status:** Active development. Used daily by the author on real projects. Core skills (peer review, security) are stable. Expect new skills and refinements regularly.

## Why This Exists

**Prompts deserve the same rigor as code.** These skills have error handling, state management, convergence criteria, and rollback logic — because without it, multi-agent workflows silently fail. Read the full [design philosophy](docs/design-philosophy.md) for the thinking behind the counter-review pattern, why markdown instead of code, and the cross-platform constraints that shaped every design decision.

**Design patterns in these skills:**

- **Counter-review** — AI critically evaluates other AI's findings instead of blindly accepting them
- **Convergence loops** — can't exit until fixes are verified clean; find → fix → verify → repeat
- **State persistence** — JSON state file survives context window compaction so variables aren't lost mid-workflow
- **Commit-ordered rollback** — MUST FIX committed before SHOULD FIX, so optional fixes can be reverted without losing critical ones
- **Decision gates** — human-in-the-loop only on disagreements, not on every finding

## Flagship: Peer Review

The core contribution — multi-agent review with counter-review, decision gates, and convergence loops. These aren't wrappers around a single AI reviewer. They orchestrate multiple agents, critically evaluate their feedback, and keep the human in the loop.

### `/peer-review-code` — Multi-Agent Code Review

[`skills/peer-review-code.md`](skills/peer-review-code.md) | Requires: git, gh, Codex CLI

Claude reviews your PR, sends it to Codex CLI and GitHub bots for independent second opinions, then **counter-reviews every finding** — agreeing, scoping down, deferring, or rejecting with justification. You break ties on rejections. Runs 2-5 rounds until all issues are resolved, with a mandatory verification round after fixes.

See a [sample review artifact](docs/examples/code-review-sample.md) to understand what the output looks like.

**How it works:**

1. **Code simplification** — Code Simplifier agent cleans up the diff before review
2. **Pre-review** — Claude's own agents (code-reviewer, silent-failure-hunter, type-design-analyzer) scan in parallel
3. **PR creation** — pushes the branch and opens a PR if one doesn't exist
4. **Multi-agent review loop** (2-5 rounds):
   - Codex CLI and GitHub bot polling run **in parallel** (adaptive timeout: 8 min round 1, 4 min round 2+)
   - Claude **counter-reviews** every finding from every source
   - GH bot findings are **verified across rounds** — tracked by fingerprint to confirm fixes are accepted
   - You resolve any rejections or deferrals at the **decision gate**
   - Claude fixes agreed findings, commits, pushes
   - Next round verifies the fixes — convergence requires all GH bot findings verified
5. **Finalize** — deferred items become GitHub issues, review artifact saved to `docs/reviews/`

**Counter-review dispositions:**

| Disposition | Meaning | Action |
|-------------|---------|--------|
| **agree** | Reviewer is right | Fix now |
| **partial** | Valid but scoped down | Fix the core issue |
| **defer** | Valid but not now | Log for later |
| **reject** | Disagree — must justify | User breaks the tie |

**What makes it different:** Most AI review tools apply all feedback blindly. This one fights back — Claude critically evaluates each suggestion before acting, and nothing is silently applied or silently ignored.

### `/peer-review-plan` — Two-Agent Plan Review

[`skills/peer-review-plan.md`](skills/peer-review-plan.md) | Requires: Codex CLI

Claude and Codex CLI take turns reviewing a plan document. Each round: Codex reviews → Claude counter-reviews with dispositions → you resolve disputes → Claude revises → repeat. Min 2 rounds, max 5. Same counter-review and decision gate patterns as code review.

**What makes it different:** Gets a second model's perspective on your architecture before you write any code. Catches blind spots that a single model misses.

### `/peer-ideate` — Multi-Model Brainstorming Council

[`skills/peer-ideate.md`](skills/peer-ideate.md) | Optional: Codex CLI, Gemini CLI

Claude, Codex, and Gemini independently brainstorm on any topic — UI design, architecture, naming, API design, tradeoffs, or any open-ended question. Claude synthesizes the raw responses into a unified findings list, then each model counter-reviews the synthesis. Final report shows consensus ideas, contested points, and unique insights ranked by confidence.

**How it works:**

1. **Capture brief** — topic, optional attachments (screenshots, code), focus areas, constraints
2. **Parallel ideation** — all three models brainstorm independently (same brief, no cross-talk)
3. **Synthesis** — Claude merges all responses, tags consensus level, preserves attribution
4. **Counter-review** — each model dispositions the synthesis (endorse / challenge / enhance / new)
5. **Final report** — consensus tiers, contested ideas with arguments from both sides, unique insights

**What makes it different:** Three models with different training biases produce genuinely diverse perspectives. The counter-review catches over- and under-weighted ideas. Works with any subset of models — degrades gracefully to Claude alone.

---

## Security Skills

Three complementary skills covering different security angles — infrastructure checks, tool-based scanning, and AI-driven analysis.

### `/security-posture` — Security Hygiene Scorecard

[`skills/security-posture.md`](skills/security-posture.md) | Requires: git. Optional: gh

Checks 16 security hygiene items across 6 categories: secrets management, dependency security, code quality gates, access control, container security, and infrastructure. Returns a letter-graded scorecard (A-F) with specific fix recommendations. No scanning tools needed — zero setup, instant results.

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

Runs Semgrep (static analysis), `npm audit` (dependency vulnerabilities), and Gitleaks (secret detection). Auto-detects which tools are installed and runs only those. Outputs a consolidated report with findings by severity.

### `/security-audit` — AI-Driven Security Review

[`skills/security-audit.md`](skills/security-audit.md) | Requires: git. Optional: Codex CLI

Deep security review using Claude + specialized agents. Codex CLI adds an independent AI assessment if installed. All findings go through counter-review before action — same disposition system as peer review.

---

## Workflow Skills

### `/merge` — Squash-Merge with Auto-Documentation

[`skills/merge.md`](skills/merge.md) | Requires: git, gh

Squash-merges the current PR, switches to the target branch, then auto-updates README, CHANGELOG, and CLAUDE.md to reflect the completed work. Includes preflight checks and safe branch cleanup.

---

## Agents

Background sub-agents invoked via the Task tool. These run alongside your work, not as slash commands.

### Codebase Snapshot

[`agents/codebase-snapshot.md`](agents/codebase-snapshot.md) — Captures architecture diagram, tech stack, file/line metrics, deployment info, and a timeline of changes since the last snapshot.

### Code Cleanup Analyst

[`agents/code-cleanup-analyst.md`](agents/code-cleanup-analyst.md) — Scans for dead code, unused imports, deprecated functions, and redundant files. Reports with confidence levels so you can remove code safely.

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
curl -o ~/.claude/commands/peer-ideate.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/skills/peer-ideate.md
curl -o ~/.claude/commands/merge.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/skills/merge.md
curl -o ~/.claude/commands/security-scan.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/skills/security-scan.md
curl -o ~/.claude/commands/security-audit.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/skills/security-audit.md
curl -o ~/.claude/commands/security-posture.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/skills/security-posture.md

# Agents
curl --create-dirs -o ~/.claude/agents/codebase-snapshot.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/agents/codebase-snapshot.md
curl --create-dirs -o ~/.claude/agents/code-cleanup-analyst.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/agents/code-cleanup-analyst.md
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
| [Codex CLI](https://github.com/openai/codex) | `npm install -g @openai/codex` | `/peer-review-code`, `/peer-review-plan`, `/peer-ideate` (optional), `/security-audit` (optional) |
| [Gemini CLI](https://github.com/google-gemini/gemini-cli) | `npm install -g @google/gemini-cli` | `/peer-ideate` (optional) |
| [Semgrep](https://semgrep.dev/) | `pip install semgrep` | `/security-scan` (optional) |
| [Gitleaks](https://github.com/gitleaks/gitleaks) | `brew install gitleaks` | `/security-scan` (optional) |

**Codex configuration:** Model and reasoning effort are inherited from `~/.codex/config.toml` — the skills do not hardcode a model:

```toml
model = "your-preferred-model"
model_reasoning_effort = "high"
```

**GitHub App Reviewers (optional):** `/peer-review-code` can collect reviews from GitHub-based AI bots in addition to the local Codex CLI review. These are entirely optional — the skill works without them, but each one adds an independent perspective.

| Bot | Install | Setup | What it does |
|-----|---------|-------|--------------|
| [Claude bot](https://github.com/apps/claude) | [Install App](https://github.com/apps/claude) | Enable "Auto-review PRs" in the app's repo settings | Reviews PRs as `@claude-bot` comments |
| [Devin](https://github.com/apps/devin-ai-integration) | [Install App](https://github.com/apps/devin-ai-integration) | Enable PR review triggers in Devin dashboard | Reviews PRs as Devin PR comments |
| [OpenAI Codex](https://github.com/apps/openai-codex) | [Install App](https://github.com/apps/openai-codex) | Enable auto-review in the Codex GitHub App settings | Reviews PRs as Codex review comments |

After installing, the skill automatically detects bot reviews on your PR and includes them in the counter-review process. No configuration needed in the skill itself — just install the app and enable its auto-review feature.

## Bash Permissions

Claude Code prompts for approval on every Bash command by default. These skills make heavy use of `git`, `gh`, `codex`, and scanning tools — without pre-approved permissions, you'll hit dozens of prompts per run.

**Recommended:** Add these to your `~/.claude/settings.json` to allow skill-related commands:

```json
{
  "permissions": {
    "allow": [
      "Bash(git *)",
      "Bash(gh *)",
      "Bash(codex *)",
      "Bash(gemini *)",
      "Bash(npm audit *)",
      "Bash(semgrep *)",
      "Bash(gitleaks *)",
      "Bash(rm -rf .review/*)"
    ]
  }
}
```

**What each permission covers:**

| Permission | Used by | Why |
|---|---|---|
| `Bash(git *)` | All skills | Branch operations, commits, push, diff |
| `Bash(gh *)` | `/peer-review-code`, `/merge`, `/security-posture` | PR creation, bot review polling, issue creation |
| `Bash(codex *)` | `/peer-review-code`, `/peer-review-plan`, `/peer-ideate`, `/security-audit` | Codex CLI exec and resume commands |
| `Bash(gemini *)` | `/peer-ideate` | Gemini CLI non-interactive prompts |
| `Bash(npm audit *)` | `/security-scan` | Dependency vulnerability scanning |
| `Bash(semgrep *)` | `/security-scan` | Static analysis |
| `Bash(gitleaks *)` | `/security-scan` | Secret detection |
| `Bash(rm -rf .review/*)` | All skills | Cleanup of temporary review files |

You only need permissions for tools you have installed. If you don't use Codex CLI, skip `Bash(codex *)`. If you don't run `/security-scan`, skip the scanning tool permissions.

**Nuclear option:** `"Bash(*)"` allows all Bash commands — convenient but grants broad access. Use the scoped list above for tighter control.

## Cross-Platform

Skills work on Windows, macOS, and Linux:
- Temp files stored in `.review/` inside the project root — avoids permission prompts. The skill auto-creates this directory and adds it to `.gitignore` on first run
- Session IDs generated natively — no shell dependencies
- File operations use Read/Write tools instead of shell commands
- Codex working directory set via `-C` flag instead of `cd` to avoid compound command approval

## License

[MIT](LICENSE)
