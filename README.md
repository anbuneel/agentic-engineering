# Agentic Engineering

Agent-agnostic workflow skills for AI coding agents. The skills add multi-agent code review, plan review, security scanning, and automated documentation workflows to Claude Code, Codex App, and Codex CLI while keeping one canonical Markdown source per workflow.

**View the [Visual Skills Guide](docs/SKILLS_GUIDE.md) for flow diagrams of every workflow.**

Each skill is a markdown file. Install it in your agent runtime, invoke the command, and the primary driver coordinates the workflow with available subagents, external model reviewers, and GitHub review agents.

## Who Is This For?

You use Claude Code, Codex App, Codex CLI, or another capable coding agent and want structured, repeatable workflows instead of ad-hoc prompting. Install a skill, run it, and the primary driver handles orchestration, counter-review, artifacts, and safety checks.

**You'll need:**
- A primary coding agent that can read Markdown instructions, inspect/edit files, and run shell commands
- Git and a GitHub repo for most workflows

**Supported primary drivers:** Claude Code, Codex App, and Codex CLI.

**Optional reviewer channels:** [Codex CLI](https://github.com/openai/codex) (`npm install -g @openai/codex`), Claude CLI reviewer channel, [Gemini CLI](https://github.com/google-gemini/gemini-cli) (`npm install -g @google/gemini-cli`), and GitHub review agents. Without them, skills degrade gracefully and record the reduced reviewer set in the artifact.

| Skill | Claude primary | Codex App primary | Codex CLI primary | Optional reviewers |
|-------|----------------|-------------------|-------------------|--------------------|
| `/multi-agent-code-review` | Yes | Yes | Yes | Claude, Codex, Gemini, GH bots |
| `/multi-agent-plan-review` | Yes | Yes | Yes | Claude, Codex, Gemini |
| `/multi-agent-ideate` | Yes | Yes | Yes | Claude, Codex, Gemini |
| `/security-posture` | Yes | Yes | Yes | gh for branch protection |
| `/security-scan` | Yes | Yes | Yes | Semgrep, Gitleaks, npm audit |
| `/security-audit` | Yes | Yes | Yes | Claude, Codex, Gemini |
| `/merge` | Yes | Yes | Yes | gh or GitHub MCP |

**Status:** Active development. Used daily by the author on real projects. Core skills (peer review, security) are stable. Expect new skills and refinements regularly.

## Why This Exists

**Prompts deserve the same rigor as code.** These skills have error handling, state management, convergence criteria, and rollback logic — because without it, multi-agent workflows silently fail. Read the full [design philosophy](docs/design-philosophy.md) for the thinking behind the counter-review pattern, why markdown instead of code, and the cross-platform constraints that shaped every design decision.

**Design patterns in these skills:**

- **Counter-review** — the primary driver critically evaluates other agents' findings instead of blindly accepting them
- **Convergence loops** — can't exit until fixes are verified clean; find → fix → verify → repeat
- **State persistence** — JSON state file survives context window compaction so variables aren't lost mid-workflow
- **Commit-ordered rollback** — MUST FIX committed before SHOULD FIX, so optional fixes can be reverted without losing critical ones
- **Decision gates** — human-in-the-loop only on disagreements, not on every finding

## Flagship: Peer Review

The core contribution — multi-agent review with counter-review, decision gates, and convergence loops. These aren't wrappers around a single AI reviewer. They orchestrate multiple agents, critically evaluate their feedback, and keep the human in the loop.

### `/multi-agent-code-review` — Multi-Agent Code Review

[`skills/multi-agent-code-review.md`](skills/multi-agent-code-review.md) | Requires: git, gh

The primary driver reviews your PR, gathers feedback from available native subagents, external CLI reviewers, and GitHub review agents, then **counter-reviews every finding** — agreeing, scoping down, deferring, or rejecting with justification. You break ties on rejections and deferrals. Runs 2-5 rounds until all issues are resolved, with a mandatory verification round after fixes.

See a [sample review artifact](docs/examples/code-review-sample.md) to understand what the output looks like.

**How it works:**

1. **Code simplification** — Claude Code may use `/simplify`; Codex and other runtimes run an equivalent inline simplification pass when safe
2. **Pre-review** — primary-native analysis and available native subagents scan in parallel
3. **PR creation** — pushes the branch and opens a PR if one doesn't exist
4. **Multi-agent review loop** (2-5 rounds):
   - External reviewers and GitHub bot polling run **in parallel** where the runtime supports it
   - The primary driver **counter-reviews** every finding from every source
   - GH bot findings are **verified across rounds** — tracked by fingerprint to confirm fixes are accepted
   - You resolve any rejections or deferrals at the **decision gate**
   - The primary driver fixes agreed findings, commits, pushes
   - Next round verifies the fixes — convergence requires all GH bot findings verified
5. **Finalize** — deferred items become GitHub issues, review artifact saved to `docs/reviews/`

**Counter-review dispositions:**

| Disposition | Meaning | Action |
|-------------|---------|--------|
| **agree** | Reviewer is right | Fix now |
| **partial** | Valid but scoped down | Fix the core issue |
| **defer** | Valid but not now | Log for later |
| **reject** | Disagree — must justify | User breaks the tie |

**What makes it different:** Most AI review tools apply all feedback blindly. This one fights back — the primary driver critically evaluates each suggestion before acting, and nothing is silently applied or silently ignored.

### `/multi-agent-plan-review` — Two-Agent Plan Review

[`skills/multi-agent-plan-review.md`](skills/multi-agent-plan-review.md) | Requires: one primary driver; external reviewers optional

The primary driver sends a plan to available external reviewers. Each round: reviewer feedback arrives -> primary driver counter-reviews with dispositions -> you resolve disputes -> primary driver revises -> repeat. Min 2 rounds, max 5. Same counter-review and decision gate patterns as code review.

**What makes it different:** Gets a second model's perspective on your architecture before you write any code. Catches blind spots that a single model misses.

### `/multi-agent-ideate` — Multi-Model Brainstorming Council

[`skills/multi-agent-ideate.md`](skills/multi-agent-ideate.md) | Optional: Claude/Codex/Gemini reviewer channels

Claude, Codex, Gemini, and the primary driver can independently brainstorm on any topic — UI design, architecture, naming, API design, tradeoffs, or any open-ended question. The primary driver synthesizes the raw responses into a unified findings list, then available participants counter-review the synthesis. Final report shows consensus ideas, contested points, and unique insights ranked by confidence.

**How it works:**

1. **Capture brief** — topic, optional attachments (screenshots, code), focus areas, constraints
2. **Parallel ideation** — all three models brainstorm independently (same brief, no cross-talk)
3. **Synthesis** — primary driver merges all responses, tags consensus level, preserves attribution
4. **Counter-review** — each model dispositions the synthesis (endorse / challenge / enhance / new)
5. **Final report** — consensus tiers, contested ideas with arguments from both sides, unique insights

**What makes it different:** Three models with different training biases produce genuinely diverse perspectives. The counter-review catches over- and under-weighted ideas. Works with any subset of models — degrades gracefully to the primary driver alone.

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

[`skills/security-audit.md`](skills/security-audit.md) | Requires: git. Optional: Claude/Codex/Gemini reviewer channels

Deep security review using the primary driver, available native subagents, and optional external reviewers. All findings go through counter-review before action — same disposition system as peer review.

---

## Workflow Skills

### `/merge` — Squash-Merge with Auto-Documentation

[`skills/merge.md`](skills/merge.md) | Requires: git + (gh or GitHub MCP)

Squash-merges the current PR, switches to the target branch, then auto-updates README, CHANGELOG, and CLAUDE.md to reflect the completed work. Includes preflight checks and evidence-based branch cleanup.

**Evidence-based cleanup:** a squash merge writes a new commit, so the feature branch head never becomes an ancestor of the target — `git branch -d` and `git branch --merged` refuse it every time and local branches pile up. The skill proves the branch content actually landed by comparing `git patch-id --verbatim` of the branch diff against the squash commit's diff, then sweeps the rest of the repository: local branches (ancestors, branches sharing a head with a merged PR, and no-PR branches settled by per-path blob and mode comparison), remote branches, and stale remote-tracking refs. Nothing is deleted without content proof, and never a protected branch, a branch held by a worktree, or one carrying commits the PR did not have.

`--verbatim` matters: the default patch-id algorithm strips whitespace, and whitespace changes behavior in Python, YAML, and Makefiles. A default-algorithm match with a verbatim mismatch is reported as a whitespace-only difference for you to judge, not acted on.

Remote branches get the same treatment: a merged PR proves what the head commit *was*, not where the branch points now, so the live tip is checked and the deletion runs under a `--force-with-lease` — a commit pushed after the merge survives and gets reported.

**Resumable and portable.** It takes `/merge <PR number or URL>`, so the feature branch need not be checked out; re-running after a successful merge resumes at the documentation step. It confirms GitHub actually merged rather than queueing the PR behind auto-merge or a merge queue, opens a follow-up docs PR when the target branch rejects direct pushes, and probes GitHub access, fetch, push, and checkout capabilities separately — reporting outstanding work instead of failing when one is missing. Fork checkouts resolve base and head repositories explicitly rather than assuming `origin`. Works with or without `gh`, running through GitHub MCP tools in remote containers.

---

## Tools

### `claude-memory-sync` — Cross-Machine Memory Sync

[`tools/claude-memory-sync/`](tools/claude-memory-sync/) | Requires: git + (jq or python3)

Syncs Claude Code's auto-generated project memories across machines via a private git repo. Handles the core problem: the same project gets different path-mangled names on each machine (`D--anbs-dev-project` on Windows vs `home-user-project` on Linux). The tool maps them to a canonical name derived from the git remote URL.

**Commands:** `setup`, `push`, `pull`, `sync`, `status`, `list`, `alias`

**How it works:**

1. `setup <repo-url>` — clones a private sync repo, creates config
2. `alias --detect` — run from inside each project to auto-detect canonical name from git remote
3. `push` / `pull` / `sync` — sync memories between local and the repo

Includes both bash and PowerShell scripts. Bash uses jq if available, falls back to python3. See the [tool README](tools/claude-memory-sync/README.md) for hook integration and full docs.

### `codex-setup-sync` — Cross-Machine Codex Setup Sync

[`tools/codex-setup-sync/`](tools/codex-setup-sync/) | Requires: git + PowerShell 5.1+

Windows-first tool for keeping Codex app/CLI setup aligned across machines via a private git repo. Syncs portable Codex config, rules, memories, user skills, and optional completed session JSONL history while explicitly excluding auth, SQLite/runtime state, AppData internals, caches, and bundled system skills.

**Commands:** `setup`, `doctor`, `status`, `push`, `pull`, `sync`, `alias`, `config print`, `session export`, `session import`

**What makes it different:** It treats Codex state as three layers — shared portable state, machine-local overlays for path-specific trust entries, and local-only runtime/auth state that should never be synced. Session import stays opt-in and experimental.

See the [tool README](tools/codex-setup-sync/README.md) for the config schema, sync repo layout, migration notes, and references to the official Codex docs.

---

## Agents

Background sub-agents for runtimes that support native subagent dispatch. Claude-compatible agent files are included today; Codex equivalents are documented as runtime prompts in this pass rather than generated as separate files.

### Codebase Snapshot

[`agents/codebase-snapshot.md`](agents/codebase-snapshot.md) — Captures architecture diagram, tech stack, file/line metrics, deployment info, and a timeline of changes since the last snapshot.

### Code Cleanup Analyst

[`agents/code-cleanup-analyst.md`](agents/code-cleanup-analyst.md) — Scans for dead code, unused imports, deprecated functions, and redundant files. Reports with confidence levels so you can remove code safely.

## Install

### Claude Code Quick Install (macOS / Linux)

```bash
git clone https://github.com/anbuneel/agentic-engineering.git
mkdir -p ~/.claude/commands ~/.claude/agents
cp agentic-engineering/skills/*.md ~/.claude/commands/
cp agentic-engineering/agents/*.md ~/.claude/agents/
```

**Want auto-sync?** Use links so edits in either location stay in sync:

```bash
git clone https://github.com/anbuneel/agentic-engineering.git
mkdir -p ~/.claude/commands ~/.claude/agents
ln agentic-engineering/skills/*.md ~/.claude/commands/
ln agentic-engineering/agents/*.md ~/.claude/agents/
```

Invoke with `/multi-agent-code-review`.

### Claude Code Quick Install (Windows)

```powershell
git clone https://github.com/anbuneel/agentic-engineering.git
Copy-Item agentic-engineering\skills\*.md ~\.claude\commands\
Copy-Item agentic-engineering\agents\*.md ~\.claude\agents\
```

**Want auto-sync?** Use symbolic links. Windows hard links only work when the repo and target directory are on the same drive; symlinks work across drives but require Developer Mode or an elevated shell.

```powershell
git clone https://github.com/anbuneel/agentic-engineering.git
Get-ChildItem agentic-engineering\skills\*.md | ForEach-Object { New-Item -ItemType SymbolicLink -Path "~\.claude\commands\$($_.Name)" -Target $_.FullName }
Get-ChildItem agentic-engineering\agents\*.md | ForEach-Object { New-Item -ItemType SymbolicLink -Path "~\.claude\agents\$($_.Name)" -Target $_.FullName }
```

### Codex Quick Install

Codex skills use `SKILL.md` inside a skill directory. For this core docs pass, keep this repo as the canonical source and install symlinks manually, through your existing Codex setup sync workflow, or with the included installer script.

Recommended layout:

```text
~/.codex/skills/
  multi-agent-code-review/SKILL.md
  multi-agent-plan-review/SKILL.md
  multi-agent-ideate/SKILL.md
  merge/SKILL.md
  security-scan/SKILL.md
  security-audit/SKILL.md
  security-posture/SKILL.md
```

Some Codex installations also load shared skills from `~/.agents/skills/`; the installer can target that layout too.

```powershell
.\scripts\install-skill-links.ps1 -Targets Codex
```

Use `-Targets Agents` for `~/.agents/skills/`, or `-Targets Claude,Codex` to link both Claude Code and Codex. The script uses symbolic links by default and falls back to copies only when symlink creation is not permitted.

Invoke from Codex with `$multi-agent-code-review` or select the skill through `/skills`. Codex plugin packaging and generated install bundles are intentionally out of scope for this pass.

### Detect Claude Sync Drift

Links can break when tools recreate files instead of editing in place. The included `scripts/check-skill-sync.sh` currently checks Claude Code command links. Add a `SessionStart` hook to `~/.claude/settings.json` to get warned at the start of every Claude Code session:

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

The script silently exits if the repo directory doesn't exist, so it's safe to add globally.

### Install Individual Files (Claude Code)

```bash
# Skills
curl -o ~/.claude/commands/multi-agent-code-review.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/skills/multi-agent-code-review.md
curl -o ~/.claude/commands/multi-agent-plan-review.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/skills/multi-agent-plan-review.md
curl -o ~/.claude/commands/multi-agent-ideate.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/skills/multi-agent-ideate.md
curl -o ~/.claude/commands/merge.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/skills/merge.md
curl -o ~/.claude/commands/security-scan.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/skills/security-scan.md
curl -o ~/.claude/commands/security-audit.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/skills/security-audit.md
curl -o ~/.claude/commands/security-posture.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/skills/security-posture.md

# Agents
curl --create-dirs -o ~/.claude/agents/codebase-snapshot.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/agents/codebase-snapshot.md
curl --create-dirs -o ~/.claude/agents/code-cleanup-analyst.md https://raw.githubusercontent.com/anbuneel/agentic-engineering/main/agents/code-cleanup-analyst.md
```

For Codex, install each skill as a directory with `SKILL.md`; generated Codex install commands are intentionally out of scope for this pass.

### Using with Other AI Tools

These are markdown files — any AI agent that can read instructions, inspect/edit files, and execute shell commands can use them. The skills now define neutral actions and runtime adapters instead of requiring one tool vocabulary.

**Verify your installation:** Run `/security-posture` in any git repo. If you see a scorecard, you're set.

## Tool Setup

**Required for all skills:**
- A primary driver: Claude Code, Codex App, Codex CLI, or another capable coding agent
- Git

**Per-skill dependencies:**

| Tool | Install | Used by |
|------|---------|---------|
| [GitHub CLI (`gh`)](https://cli.github.com/) | `brew install gh` then `gh auth login` | `/multi-agent-code-review`, `/merge` (gh or GitHub MCP), `/security-posture` (optional) |
| [Claude Code](https://claude.ai/code) | Follow Claude Code docs | Primary driver or external reviewer channel |
| [Codex CLI](https://github.com/openai/codex) | `npm install -g @openai/codex` | Primary driver or external reviewer channel |
| [Gemini CLI](https://github.com/google-gemini/gemini-cli) | `npm install -g @google/gemini-cli` | Multi-agent workflows (optional) |
| [Semgrep](https://semgrep.dev/) | `pip install semgrep` | `/security-scan` (optional) |
| [Gitleaks](https://github.com/gitleaks/gitleaks) | `brew install gitleaks` | `/security-scan` (optional) |

**Runtime detection:** Skills set `PRIMARY_DRIVER` from the active runtime. Claude Code command contexts use `claude-code`; Codex desktop contexts use `codex-app`; `codex exec` contexts use `codex-cli`; ambiguous runtimes use `unknown` and fall back to neutral capabilities unless behavior would materially differ.

**Effort configuration:** Skills accept `effort=<fast|balanced|deep>` as cross-agent intent. Claude Code also keeps the compatibility option `model=<sonnet|opus|haiku>` for Claude-native subagent dispatch.

| Effort | Claude-native / Claude CLI | Codex CLI | Intended use |
|--------|-----------------------------|-----------|--------------|
| `fast` | Prefer Haiku when selecting a Claude model; pass `--effort low` when supported | Prefer inherited config; optional `-c model_reasoning_effort="low"` | Quick pass |
| `balanced` | Prefer Sonnet when selecting a Claude model; pass `--effort medium` when supported | Prefer inherited config; optional `-c model_reasoning_effort="medium"` | Default |
| `deep` | Prefer Opus when selecting a Claude model and cost is acceptable; pass `--effort high` when supported | Prefer inherited config; optional `-c model_reasoning_effort="high"` | High-stakes review |

`model=<sonnet|opus|haiku>` overrides only Claude model selection. Codex model selection is inherited from `~/.codex/config.toml`; the skills do not hardcode Codex `-m`.

**Codex configuration:** Model and reasoning effort are inherited from `~/.codex/config.toml` — the skills do not hardcode a model:

```toml
model = "your-preferred-model"
model_reasoning_effort = "high"
```

**Claude reviewer channel:** When Codex is primary, multi-agent workflows can call Claude CLI as an independent reviewer:

```bash
claude -p "<review prompt>. Do not modify files. End with exactly: VERDICT: APPROVED or VERDICT: REVISE" --permission-mode plan --allowedTools "Read" "Grep" "Glob" --disallowedTools "Edit" "Write" "MultiEdit" --output-format json
```

The skill launches Claude CLI with command cwd set to `PROJECT_ROOT`, parses `session_id` from Claude's JSON output, stores it as `externalThreadIds.claude`, writes `result` to `.review/`, and resumes later rounds with `--resume`. Claude has no `-C` equivalent, so runtimes that cannot set command cwd should add `--add-dir "${PROJECT_ROOT}"` and include the repo root in the prompt.

**GitHub App Reviewers (optional):** `/multi-agent-code-review` can collect reviews from GitHub-based AI bots regardless of whether Claude or Codex is the primary driver. These are entirely optional — the skill works without them, but each one adds an independent perspective.

| Bot | Install | Setup | What it does |
|-----|---------|-------|--------------|
| [Claude bot](https://github.com/apps/claude) | [Install App](https://github.com/apps/claude) | Enable "Auto-review PRs" in the app's repo settings | Reviews PRs as `@claude-bot` comments |
| [Devin](https://github.com/apps/devin-ai-integration) | [Install App](https://github.com/apps/devin-ai-integration) | Enable PR review triggers in Devin dashboard | Reviews PRs as Devin PR comments |
| [OpenAI Codex](https://github.com/apps/openai-codex) | [Install App](https://github.com/apps/openai-codex) | Enable auto-review in the Codex GitHub App settings | Reviews PRs as Codex review comments |

After installing, the skill automatically detects bot reviews on your PR and includes them in the counter-review process. No configuration needed in the skill itself — just install the app and enable its auto-review feature.

## Runtime Permissions

Agent runtimes may prompt for approval on shell commands. These skills make heavy use of `git`, `gh`, external reviewer CLIs, and scanning tools. Configure permissions according to your primary driver.

When Codex is primary, external reviewer subprocesses (`claude`, `gemini`, and optional secondary `codex`) need sandbox and approval settings that allow launching those CLIs and using their network-backed model sessions. If a reviewer is policy-blocked, the skill records it as skipped and continues unless you explicitly required that reviewer.

**Claude Code recommended:** Add these to your `~/.claude/settings.json` to allow skill-related commands:

```json
{
  "permissions": {
    "allow": [
      "Bash(git *)",
      "Bash(gh *)",
      "Bash(claude *)",
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
| `Bash(gh *)` | `/multi-agent-code-review`, `/merge`, `/security-posture` | PR creation, bot review polling, issue creation |
| GitHub MCP tools | `/merge` | Fallback for `gh` in remote containers that ship without the CLI |
| `Bash(claude *)` | multi-agent workflows when Codex is primary | Claude reviewer channel |
| `Bash(codex *)` | multi-agent workflows when Codex is external or secondary | Codex CLI exec and resume commands |
| `Bash(gemini *)` | `/multi-agent-ideate` | Gemini CLI non-interactive prompts |
| `Bash(npm audit *)` | `/security-scan` | Dependency vulnerability scanning |
| `Bash(semgrep *)` | `/security-scan` | Static analysis |
| `Bash(gitleaks *)` | `/security-scan` | Secret detection |
| `Bash(rm -rf .review/*)` | All skills | Cleanup of temporary review files |

You only need permissions for tools you have installed. If you don't use a reviewer channel, skip its permission. If you don't run `/security-scan`, skip the scanning tool permissions.

**Nuclear option:** `"Bash(*)"` allows all Bash commands — convenient but grants broad access. Use the scoped list above for tighter control.

## Cross-Platform

Skills are designed to work on Windows, macOS, and Linux:
- Temp files stored in `.review/` inside the project root — avoids permission prompts. The skill auto-creates this directory and adds it to `.gitignore` on first run
- Session IDs generated natively — no shell dependencies
- File operations use the primary driver's native file tools instead of shell commands
- Codex working directory set via `-C` flag instead of `cd` to avoid compound command approval

## License

[MIT](LICENSE)
