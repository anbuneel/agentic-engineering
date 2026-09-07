# Agentic Engineering

Agent-agnostic workflow skills for AI coding agents. The skills add multi-agent code review, plan review, security scanning, and automated documentation workflows to Claude Code, Codex App, and Codex CLI while keeping one canonical Markdown source per workflow.

**View the [Visual Skills Guide](docs/SKILLS_GUIDE.md) for flow diagrams of every workflow.**

Each skill is a markdown file. Install the plugin once per machine, invoke the skill, and the primary driver coordinates the workflow with available subagents, external model reviewers, and GitHub review agents. Skill names below are shown bare; in Claude Code they carry the plugin prefix (`/ae:merge`), in Codex they are `$merge`.

## Who Is This For?

You use Claude Code, Codex App, Codex CLI, or another capable coding agent and want structured, repeatable workflows instead of ad-hoc prompting. Install a skill, run it, and the primary driver handles orchestration, counter-review, artifacts, and safety checks.

**You'll need:**
- A primary coding agent that can read Markdown instructions, inspect/edit files, and run shell commands
- Git and a GitHub repo for most workflows

**Supported primary drivers:** Claude Code, Codex App, and Codex CLI.

**Optional reviewer channels:** [Codex CLI](https://github.com/openai/codex) (`npm install -g @openai/codex`), Claude CLI reviewer channel, and GitHub review agents. Without them, skills degrade gracefully and record the reduced reviewer set in the artifact.

| Skill | Claude primary | Codex App primary | Codex CLI primary | Optional reviewers |
|-------|----------------|-------------------|-------------------|--------------------|
| `/multi-agent-code-review` | Yes | Yes | Yes | Claude, Codex, GH bots |
| `/multi-agent-plan-review` | Yes | Yes | Yes | Claude, Codex |
| `/multi-agent-ideate` | Yes | Yes | Yes | Claude, Codex |
| `/security-posture` | Yes | Yes | Yes | gh for branch protection |
| `/security-scan` | Yes | Yes | Yes | Semgrep, Gitleaks, npm audit |
| `/security-audit` | Yes | Yes | Yes | Claude, Codex |
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

[`skills/multi-agent-code-review/SKILL.md`](skills/multi-agent-code-review/SKILL.md) | Requires: git, gh

The primary driver reviews your PR, gathers feedback from the three review lenses, the cross-family CLI reviewer, and GitHub review agents, then **counter-reviews every finding** — agreeing, scoping down, deferring, or rejecting with justification. Rejections and deferrals never block the loop: they are recorded with both sides' arguments and handed to you at the end under "Needs your call". Round 1 fans out to everyone; a verification round runs only after fixes, and only for the reviewers whose findings were acted on. A clean round 1 converges immediately; the cap is 5 rounds.

See a [sample review artifact](docs/examples/code-review-sample.md) to understand what the output looks like.

**How it works:**

1. **Preflight** — clean tree, base branch, quality gates (from the project's `CLAUDE.md`/`AGENTS.md` or detected from the build files), findings schema, one rebase check, PR created if missing
2. **Round 1** — the three lens agents, the cross-family CLI reviewer, and GitHub bot polling run **in parallel**; every reviewer returns one findings object
3. **Counter-review** — the primary driver dispositions every finding; reject and defer go to **Needs your call** without stopping the loop (`decisions=interactive` to be asked mid-loop instead)
4. **Fix** — MUST_FIX committed first as a checkpoint, then SHOULD_FIX; quality gates after each batch; push; round summary posted to the PR
5. **Verification rounds** — only when fixes landed: resume just the reviewers whose findings were acted on, poll bots only after a push, verify GH bot findings by fingerprint
6. **Finalize** — Needs your call presented, deferred items become GitHub issues, PR description and final comment updated, full audit trail saved to `docs/reviews/`

**Counter-review dispositions:**

| Disposition | Meaning | Action |
|-------------|---------|--------|
| **agree** | Reviewer is right | Fix now |
| **partial** | Valid but scoped down | Fix the core issue |
| **defer** | Valid but not now | Needs your call, becomes an issue at finalize |
| **reject** | Disagree — must justify | Needs your call, both arguments recorded |

**What makes it different:** Most AI review tools apply all feedback blindly. This one fights back — the primary driver critically evaluates each suggestion before acting, and nothing is silently applied or silently ignored. Because the loop never waits on you, it runs the same way in a terminal, a desktop app worktree, or a background session.

### `/multi-agent-plan-review` — Two-Agent Plan Review

[`skills/multi-agent-plan-review/SKILL.md`](skills/multi-agent-plan-review/SKILL.md) | Requires: one primary driver; external reviewers optional

The primary driver sends a plan to the cross-family reviewer. Each round: findings arrive as one JSON object -> primary driver counter-reviews with dispositions -> agreed items revise the plan -> the reviewer session is resumed to verify. Reject and defer go to Needs your call without stopping the loop. A round with nothing to revise converges; max 5 rounds. Same patterns as code review.

**What makes it different:** Gets a second model's perspective on your architecture before you write any code. Catches blind spots that a single model misses.

### `/multi-agent-ideate` — Multi-Model Brainstorming Council

[`skills/multi-agent-ideate/SKILL.md`](skills/multi-agent-ideate/SKILL.md) | Optional: Claude/Codex reviewer channels

Claude, Codex, and the primary driver can independently brainstorm on any topic — UI design, architecture, naming, API design, tradeoffs, or any open-ended question. The primary driver synthesizes the raw responses into a unified findings list, then available participants counter-review the synthesis. Final report shows consensus ideas, contested points, and unique insights ranked by confidence.

**How it works:**

1. **Capture brief** — topic, optional attachments (screenshots, code), focus areas, constraints
2. **Parallel ideation** — every available participant brainstorms independently (same brief, no cross-talk)
3. **Synthesis** — primary driver merges all responses, tags consensus level, preserves attribution
4. **Counter-review** — each model dispositions the synthesis (endorse / challenge / enhance / new)
5. **Final report** — consensus tiers, contested ideas with arguments from both sides, unique insights

**What makes it different:** Two model families with different training biases produce genuinely diverse perspectives. The counter-review catches over- and under-weighted ideas. Works with any subset of models — degrades gracefully to the primary driver alone.

---

## Security Skills

Three complementary skills covering different security angles — infrastructure checks, tool-based scanning, and AI-driven analysis.

### `/security-posture` — Security Hygiene Scorecard

[`skills/security-posture/SKILL.md`](skills/security-posture/SKILL.md) | Requires: git. Optional: gh

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

[`skills/security-scan/SKILL.md`](skills/security-scan/SKILL.md) | Requires: git + at least one of Semgrep, Gitleaks, or npm

Runs Semgrep (static analysis), `npm audit` (dependency vulnerabilities), and Gitleaks (secret detection). Auto-detects which tools are installed and runs only those. Outputs a consolidated report with findings by severity.

### `/security-audit` — AI-Driven Security Review

[`skills/security-audit/SKILL.md`](skills/security-audit/SKILL.md) | Requires: git. Optional: Claude/Codex reviewer channels

Deep security review using the primary driver, available native subagents, and optional external reviewers. All findings go through counter-review before action — same disposition system as peer review.

---

## Workflow Skills

### `/merge` — Squash-Merge with Auto-Documentation

[`skills/merge/SKILL.md`](skills/merge/SKILL.md) | Requires: git + (gh or GitHub MCP)

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

Background sub-agents for runtimes that support native subagent dispatch. Claude-compatible agent files are included today; Codex runs the same prompts as primary-native passes.

### Review Lenses

[`agents/code-reviewer.md`](agents/code-reviewer.md), [`agents/silent-failure-hunter.md`](agents/silent-failure-hunter.md), [`agents/type-design-analyzer.md`](agents/type-design-analyzer.md) — Read-only review lenses used by `/multi-agent-code-review` and `/security-audit`. Correctness and security, silent failures and fail-open paths, and type soundness and design. Each takes its scope, severity scale, and output format from the task prompt.

### Codebase Snapshot

[`agents/codebase-snapshot.md`](agents/codebase-snapshot.md) — Captures architecture diagram, tech stack, file/line metrics, deployment info, and a timeline of changes since the last snapshot.

### Code Cleanup Analyst

[`agents/code-cleanup-analyst.md`](agents/code-cleanup-analyst.md) — Scans for dead code, unused imports, deprecated functions, and redundant files. Reports with confidence levels so you can remove code safely.

## Install

This repo is a plugin for both Claude Code and Codex. Install it once per machine and every project on that machine gets the skills, including git worktrees and the Codex desktop app. Each skill lives at `skills/<name>/SKILL.md` and follows the [Agent Skills](https://agentskills.io/specification) format.

### Claude Code

```bash
claude plugin marketplace add anbuneel/agentic-engineering
claude plugin install ae@agentic-engineering
```

Plugin skills are namespaced, so invoke them as `/ae:multi-agent-code-review`, `/ae:merge`, and so on. The agents under `agents/` install with the plugin.

**Cloud sessions** never read your user-level plugins. Commit this to a project's `.claude/settings.json` and cloud sessions install the plugin when they start:

```json
{
  "extraKnownMarketplaces": {
    "agentic-engineering": {
      "source": { "source": "github", "repo": "anbuneel/agentic-engineering" }
    }
  },
  "enabledPlugins": {
    "ae@agentic-engineering": true
  }
}
```

### Codex

```bash
codex plugin marketplace add anbuneel/agentic-engineering
codex plugin add ae@agentic-engineering
```

Invoke with `$multi-agent-code-review` or pick the skill from `/skills`. The desktop app and its worktrees share this install. Codex cloud does not load plugins; to use these skills there, copy the `skills/<name>/` directories you need into that repository's `.agents/skills/`.

### Update

Both tools install a snapshot and refresh it when the plugin version changes. To release: bump with `.\scripts\Set-PluginVersion.ps1 -Version x.y.z`, commit, then run `claude plugin update ae@agentic-engineering` or `codex plugin marketplace upgrade` on each machine.

### Develop Locally

`claude --plugin-dir <path-to-repo>` loads the working tree directly, and `/reload-plugins` picks up edits. For Codex, register the checkout as a local marketplace with `codex plugin marketplace add <path-to-repo>` and then `codex plugin add ae@agentic-engineering`.

Run `claude plugin validate <path-to-repo>` before opening a PR. It checks the plugin and marketplace manifests, every `SKILL.md`, and the agent frontmatter.

### Using with Other AI Tools

These are markdown files — any AI agent that can read instructions, inspect/edit files, and execute shell commands can use them. The skills define neutral actions and runtime adapters instead of requiring one tool vocabulary. Any tool that reads the Agent Skills layout can load `skills/<name>/SKILL.md` directly.

**Verify your installation:** Run `/ae:security-posture` (Claude Code) or `$security-posture` (Codex) in any git repo. If you see a scorecard, you're set.

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
| [Semgrep](https://semgrep.dev/) | `pip install semgrep` | `/security-scan` (optional) |
| [Gitleaks](https://github.com/gitleaks/gitleaks) | `brew install gitleaks` | `/security-scan` (optional) |

**Runtime detection:** Skills set `PRIMARY_DRIVER` from the active runtime. Claude Code command contexts use `claude-code`; Codex desktop contexts use `codex-app`; `codex exec` contexts use `codex-cli`; ambiguous runtimes use `unknown` and fall back to neutral capabilities unless behavior would materially differ.

**Models and effort:** Every driver inherits the model you configured: Claude Code's settings for Claude, `~/.codex/config.toml` for Codex. The skills never pick a model tier. `effort=<fast|balanced|deep>` maps to reasoning effort only:

| Effort | Claude CLI and subagents | Codex CLI | Intended use |
|--------|--------------------------|-----------|--------------|
| `fast` | inherit model, `--effort low` | `-c model_reasoning_effort="low"` | Quick pass |
| `balanced` | inherit model and configured effort | inherit both | Default |
| `deep` | inherit model, `--effort xhigh` | `-c model_reasoning_effort="xhigh"` | High-stakes review |

`model=<fable|opus|sonnet|haiku>` overrides the Claude model only. `budget=<usd>` caps each Claude reviewer run with `--max-budget-usd`; there is no cap by default, and a headless Claude run costs roughly 0.3 to 0.7 USD before any review work, so caps under 2 USD abort early.

**Reviewer contracts:** Each multi-agent skill ships `references/reviewer-contracts.md` and `references/findings-schema.md`. The Claude channel runs `claude -p` with `--permission-mode plan --permission-prompts none`, a read-only tool list, `--output-format json`, and `--json-schema`; the Codex channel runs `codex exec --json -s read-only -C <root> --output-schema <file> -o <file>`. Both return one findings object per round, both sessions are resumed across rounds, and the primary driver counter-reviews every finding regardless of the reviewer's verdict.

**Review lenses:** Three read-only agents install with the plugin and run in parallel as independent lenses: `code-reviewer`, `silent-failure-hunter`, and `type-design-analyzer`. Under Codex they run as primary-native passes unless Codex custom agents are configured.

**GitHub App Reviewers (optional):** `/multi-agent-code-review` can collect reviews from GitHub-based AI bots regardless of whether Claude or Codex is the primary driver. These are entirely optional — the skill works without them, but each one adds an independent perspective.

| Bot | Install | Setup | What it does |
|-----|---------|-------|--------------|
| [Claude bot](https://github.com/apps/claude) | [Install App](https://github.com/apps/claude) | Enable "Auto-review PRs" in the app's repo settings | Reviews PRs as `@claude-bot` comments |
| [Devin](https://github.com/apps/devin-ai-integration) | [Install App](https://github.com/apps/devin-ai-integration) | Enable PR review triggers in Devin dashboard | Reviews PRs as Devin PR comments |
| [OpenAI Codex](https://github.com/apps/openai-codex) | [Install App](https://github.com/apps/openai-codex) | Enable auto-review in the Codex GitHub App settings | Reviews PRs as Codex review comments |

After installing, the skill automatically detects bot reviews on your PR and includes them in the counter-review process. No configuration needed in the skill itself — just install the app and enable its auto-review feature.

## Runtime Permissions

Agent runtimes may prompt for approval on shell commands. These skills make heavy use of `git`, `gh`, external reviewer CLIs, and scanning tools. Configure permissions according to your primary driver.

When Codex is primary, external reviewer subprocesses (`claude` and optional secondary `codex`) need sandbox and approval settings that allow launching those CLIs and using their network-backed model sessions. If a reviewer is policy-blocked, the skill records it as skipped and continues unless you explicitly required that reviewer.

**Claude Code recommended:** Add these to your `~/.claude/settings.json` to allow skill-related commands:

```json
{
  "permissions": {
    "allow": [
      "Bash(git *)",
      "Bash(gh *)",
      "Bash(claude *)",
      "Bash(codex *)",
      "Bash(npm audit *)",
      "Bash(semgrep *)",
      "Bash(gitleaks *)"
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
| `Bash(npm audit *)` | `/security-scan` | Dependency vulnerability scanning |
| `Bash(semgrep *)` | `/security-scan` | Static analysis |
| `Bash(gitleaks *)` | `/security-scan` | Secret detection |

Skills leave `.review/` in place; it is gitignored and every file carries the run id, so no delete permission is needed.

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
