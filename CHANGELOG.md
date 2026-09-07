# Changelog

All notable changes to this project are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Changed
- Skills moved from `skills/<name>.md` to `skills/<name>/SKILL.md` to follow the Agent Skills specification; each directory name now equals the frontmatter `name`
- The repo is now a plugin for both Claude Code (`.claude-plugin/`) and Codex (`.codex-plugin/`, `.agents/plugins/`), published as `ae`. One install per machine covers every project, worktree, and the Codex desktop app; Claude Code invokes skills as `/ae:<name>`
- Reviewer channels are Claude and Codex only. Gemini CLI support was removed from every skill, the docs, and the sample artifact
- `effort=` no longer picks a Claude model tier. Every driver inherits the user's configured model; effort maps to `--effort low|xhigh` on Claude and `-c model_reasoning_effort` on Codex. `model=` accepts `fable|opus|sonnet|haiku`, and `budget=<usd>` caps Claude reviewer runs
- External reviewers return one JSON findings object per round, enforced with `--json-schema` on Claude and `--output-schema` on Codex, instead of a `VERDICT:` line parsed out of prose. Codex output is read from the `-o` file rather than scraped from `item.completed` events; Claude output is read from `structured_output`
- Reviewer command contracts and the findings schema moved into each multi-agent skill's `references/` directory (identical copies, per the Agent Skills layout), which brings every `SKILL.md` under the 500-line guideline
- `/multi-agent-code-review` sequence rewritten. Round 1 fans out to every reviewer; a verification round runs only after fixes and re-engages only the reviewers whose findings were acted on; bots are polled only after a push; a clean round 1 converges instead of always running two rounds. The pre-review and loop pipelines are one pipeline
- `/multi-agent-code-review` no longer blocks on the user. Reject and defer dispositions are recorded with both arguments under "Needs your call" and presented at finalize; `decisions=interactive` restores the mid-loop question. `require=<reviewer>` makes a reviewer mandatory
- `/multi-agent-code-review` rebases once at preflight and reports a moved base at finalize instead of rebasing every round, which invalidated resumed reviewer sessions
- `/multi-agent-code-review` quality gates come from a `Quality gates` section in the project's `CLAUDE.md` or `AGENTS.md` when present, else are detected from `package.json` (with the right package manager, including pnpm and turbo roots), `pyproject.toml`, `Cargo.toml`, or `go.mod`
- `/multi-agent-plan-review` follows the same loop shape: reject and defer go to Needs your call instead of a blocking gate (`decisions=interactive` to opt back in), a round with nothing to revise converges instead of always running two rounds, and an advisory reviewer's `REVISE` verdict no longer forces another round; `require=<reviewer>` makes one mandatory
- Skills no longer delete `.review/`. It is gitignored and every file carries the run id, so the `rm -rf` step and its permission are gone from every skill

### Removed
- The simplification pass at the start of `/multi-agent-code-review`. It committed an unreviewed refactor before any reviewer saw the code and was Claude-only; run `/simplify` separately when wanted
- `scripts/install-skill-links.ps1`, its Pester tests, and `scripts/check-skill-sync.sh`. Plugin installs are cached and updated by the tools themselves, so per-runtime symlinks and the drift check have nothing left to do

### Added
- `scripts/Set-PluginVersion.ps1` bumps the version in every plugin manifest before a release
- `agents/code-reviewer.md`, `agents/silent-failure-hunter.md`, `agents/type-design-analyzer.md` — the three review lenses the multi-agent skills dispatch. They were previously assumed to be Claude Code built-ins, which no longer exist, so the skills silently fell back to the primary driver reviewing itself

### Fixed
- Agent frontmatter for `codebase-snapshot` and `code-cleanup-analyst` did not parse: the descriptions embedded unquoted `<example>` blocks with `: ` sequences, so every field after `name` was silently dropped at load time and the agents ran with default tools and model. Descriptions are folded block scalars now, and the stale Playwright MCP tool list is gone
- `/merge` never checked the local target branch against its remote, so a PR branched from a stale target silently carried that target's unpushed commits into the squash — GitHub diffs a PR from its merge-base with the base branch, not from the commit you branched at. Step 1e now counts ahead/behind with `git rev-list --left-right --count`, tests each unpushed commit against the PR head with `merge-base --is-ancestor`, and stops before merging when any of them would be absorbed. Previously the only signal was Step 3's `pull --ff-only` refusing — correct, but after the irreversible merge

- `scripts/check-skill-sync.sh` only checked `~/.claude/commands`, so a stale skill in `$CODEX_HOME/skills` stayed invisible while the Claude symlink reported clean — which is how a pre-release copy of `/merge` sat installed for Codex through an entire round of fixes. It now checks Claude commands and agents, `$CODEX_HOME/skills`, and `~/.agents/skills`, reporting a root only when that root is already in use and only for git-tracked files, so single-runtime installs and work-in-progress skills produce no noise
- `scripts/install-skill-links.ps1` returned early on "Already linked" before consulting `-Mode`, so an explicit `-Mode Copy` was silently skipped whenever the destination was already a correct symlink, and the run reported success without replacing it

### Added
- `scripts/tests/install-skill-links.Tests.ps1` — Pester coverage for the installer's mode handling, including a regression test that fakes the "already linked" answer so the Copy-mode fix stays verified on machines where symlink creation needs elevation
- `tools/codex-setup-sync/` — Windows-first PowerShell tool for syncing portable Codex setup across machines through a private git repo
- Config rendering, machine-local overlays, optional session export/import, wrapper generation, and Pester coverage for `codex-setup-sync`
- Agent-agnostic reviewer registry model for shipped skills, covering primary driver, native subagents, external CLI reviewers, common GitHub review agents, skipped reviewers, and reviewer independence notes
- `scripts/install-skill-links.ps1` for symlinking shipped skills into Claude Code, Codex `$CODEX_HOME/skills`, or shared `~/.agents/skills`

### Changed
- Reframed shipped skills and docs from Claude-first workflows to Claude/Codex-compatible primary-driver workflows
- Updated multi-agent review, plan review, ideation, and security audit flows to support dynamic reviewer discovery and degraded-mode artifacts
- Tightened reviewer contracts with concrete Claude CLI invocation/resume semantics, advisory-vs-required reviewer rules, Codex sandbox prerequisites, and same-family reviewer labeling
- Hardened headless Claude reviewer commands with explicit read-only tool grants, edit/write denials, and `PROJECT_ROOT` cwd requirements
- Replaced Windows hard-link install guidance with symbolic-link guidance for cross-drive development setups

### Fixed
- `/merge` branch cleanup never worked on a squash merge — `git branch -d` and `git branch --merged` both test ancestry, and a squash merge writes a new commit so the branch head is never an ancestor of the target. Step 6 now proves the branch content landed by comparing `git patch-id --stable` of the branch diff against the squash commit's diff, and deletes with `-D` on that proof
- `/merge` rule "do NOT force-delete branches" is replaced by "never delete without content proof" — the old rule was what stranded every merged branch
- `/merge` only ever considered the PR's own branch, so branches sharing a head with a merged PR and branches with no PR accumulated unnoticed — added a repo-wide sweep that classifies every local branch (ancestor, squashed-in, unique content, checked out in a worktree) and settles no-PR branches by per-file blob hashes
- `/merge` assumed `gh` was installed — GitHub operations now have both a `gh` path and a GitHub MCP path, detected once in preflight, so the skill runs in remote containers that ship without the CLI
- `/merge` errored when the merged branch was absent from a fresh container clone, and could act on missing history in a shallow clone — absent is now reported as normal, shallow history is deepened before verification, and anything unverifiable is kept
- `/merge` never reported branches it left behind — Step 7 now ends with an inventory of every remaining local branch and the reason it was kept
- `/merge` passed `--delete-branch` to `gh pr merge` while claiming it left local branches alone; `gh` documents it as deleting the local branch too, so cleanup could happen before any verification. The flag is gone and remote deletion is explicit
- `/merge` treated a successful `gh pr merge` as a completed merge — auto-merge and merge queues leave the PR open with no squash commit. The merge is now confirmed against the PR state before anything is verified or documented
- `/merge` proved branch content with the default `git patch-id`, which strips whitespace and so could not support its "exactly what landed" claim. Deletion evidence is now `--verbatim`; a whitespace-only difference is reported for the user to judge instead of acted on
- `/merge` required its feature branch to be checked out and refused to run once the PR was merged, so an interrupted run could not be finished. It now accepts `/merge <PR number or URL>`, and an already-merged PR resumes at the documentation step
- `/merge` pushed docs directly to the target branch, which fails on repositories that require pull requests — a rejected push now becomes a follow-up docs PR, and push failures are classified rather than retried
- `/merge` inferred every capability from one `gh`-versus-MCP switch. GitHub access, fetch, push, and local checkout are now probed separately, and missing ones are reported as outstanding work
- `/merge` assumed `origin` held the PR head, which is wrong for fork PRs, and never deleted a branch in a fork. Base and head repositories are now resolved explicitly
- `/merge` compared no-PR branches by surviving blob hashes alone, missing deletions, renames, and mode changes — it now requires every `--name-status` entry to be accounted for
- `/merge` deleted the remote head branch on the strength of the merge alone, destroying any commit pushed to it after the merge — the live tip is now checked against the merged head SHA and the deletion runs under a `--force-with-lease` on that SHA
- `/merge` recorded the resolved base and head repositories but kept using bare PR numbers and a hardcoded `origin`, which targets the wrong repository in a fork checkout — `--repo` is now passed to every `gh` call and every git remote operation names `BASE_REMOTE` or `HEAD_REMOTE`. The blanket "never delete a fork branch" rule, which contradicted the fork-checkout case, is replaced by "delete the head branch only through the remote that holds it"
- `/merge` still pulled and pushed documentation through bare `git pull`/`git push`, which follow the branch's tracking configuration and so target the fork in a fork checkout — every pull, push, and fetch now names its remote and refspec, including the follow-up docs PR, which falls back to pushing the branch to the fork when the base repository refuses it
- `/merge` preflight was circular: it probed reachability with `BASE_REMOTE` before resolving it, while the PR lookup needed a `BASE_REPO` that was not yet known, and the MCP path resolved a bare PR number against `origin` where the same number is a different PR. Step 1 now resolves repository, then PR, then remotes, then capabilities, and a bare number that cannot be attributed to one repository stops for confirmation
- `/merge` reused the worktree map captured before Step 3 switched branches, so a run started on the feature branch classified it as checked out and never deleted it — reintroducing the very defect this release fixes. The map is refreshed after the checkout and again immediately before deletion
- `/merge` could adopt another worktree to hold the target branch without checking that worktree was clean, sweeping unrelated edits into the docs commit — every step from Step 3 on now runs against an explicit `WORK_ROOT` whose cleanliness is verified where it actually lands
- `/merge` swept only local branches and could delete against evidence gathered moments earlier — the sweep now covers remote branches and stale remote-tracking refs, protects integration branches, pages through PR listings, and re-checks each branch tip immediately before deletion

## [0.7.0] - 2026-03-10

### Changed
- Renamed `peer-review-code` → `multi-agent-code-review` for clarity with external users
- Renamed `peer-review-plan` → `multi-agent-plan-review`
- Renamed `peer-ideate` → `multi-agent-ideate`
- Updated all references across README, CLAUDE.md, SKILLS_GUIDE, CONTRIBUTING, templates, and examples

## [0.6.6] - 2025-02-27

### Added
- "Why This Exists" section in README — motivation, prompt-as-code philosophy, counter-review origin, and why markdown over traditional code

### Removed
- All references to unreleased predecessor project

## [0.6.5] - 2025-02-27

### Added
- Markdownlint GitHub Action for CI on push and PRs
- Markdownlint config (`.markdownlint.json`) with sensible defaults for skill files

### Changed
- Rewrote README opening for instant clarity — leads with what it does, not abstract descriptions
- Better Codex CLI explanation — now explains *why* (independent second opinion from a different model)
- License year updated to 2025-2026

## [0.6.4] - 2025-02-27

### Added
- Sample review artifact (`docs/examples/code-review-sample.md`) showing full peer-review-code output with counter-review, decision gates, and convergence
- Install verification one-liner in Quick Start section

### Changed
- Softened "agent-agnostic" claim to "adaptable to other AI coding agents"
- Removed placeholder model name from Codex config example — now says "your-preferred-model"

## [0.6.3] - 2025-02-27

### Fixed
- Merge skill checked out repo default branch instead of PR's actual target branch — now uses `baseRefName` from the PR, supporting release/hotfix flows
- Split compound `git checkout && git pull` into separate commands for prompt/approval reliability

## [0.6.2] - 2025-02-27

### Fixed
- Security-posture branch protection check hardcoded to `main`/`master` — now detects default branch via `gh repo view`
- Wording drift in merge skill heading ("Switch to Main" → "Switch to Default Branch")

## [0.6.1] - 2025-02-27

### Fixed
- Uninitialized `BRANCH` and `BASE_BRANCH` variables in peer-review-code — now captured in preflight and persisted in state file
- Peer-review-code preflight only blocked `main`/`master` — now detects default branch dynamically via `gh repo view`
- Undefined `${ROUND}` in peer-review-plan fallback command
- Missing `$` in peer-review-plan artifact path (`{REVIEW_ID}` → `${REVIEW_ID}`)

## [0.6.0] - 2025-02-27

### Added
- `SECURITY.md` with vulnerability disclosure policy
- Codex CLI compatibility table in README — shows which skills need it and which don't
- GitHub issue templates (bug report, skill request) and PR template

### Changed
- README restructured: "Who Is This For?" section, quick-start moved above install, expanded skill/agent descriptions, LICENSE linked
- CLAUDE.md sanitized — replaced personal paths with generic cross-platform instructions

### Fixed
- Broken `/security-review` reference → `/security-audit` in security-posture skill
- Unresolved `{owner}/{repo}` in security-posture branch protection check — now resolves via `gh repo view`
- Destructive `git clean -fd` removed from peer-review-code revert logic
- Replaced `rm`, `2>/dev/null`, and shell redirects with cross-platform agent file tools across all skills
- Hardcoded `git checkout main` in merge skill — now detects default branch dynamically

## [0.5.0] - 2025-02-27

### Added
- `/security-scan` skill — SAST, dependency audit, and secret detection
- `/security-audit` skill — full-codebase AI security review with multi-agent counter-review
- `/security-posture` skill — security hygiene baseline check with scorecard and letter grade
- LICENSE file (MIT)
- `.gitignore` for skill artifacts and OS files
- `CONTRIBUTING.md` with skill/agent authoring guidelines
- This changelog

### Changed
- Expanded `/merge` skill with preflight checks, failure handling, and safe branch cleanup
- Added quick-start section to README with sample output

## [0.4.0] - 2025-02-19

### Added
- Verification round requirement — fixes must be re-reviewed before convergence
- State file persistence for Codex resume commands (survives context compaction)

### Fixed
- Reduced permission prompts in security skills

## [0.3.0] - 2025-02-14

### Added
- Code-simplifier agent as first step in code review pipeline
- Bash command safety rules for code-simplifier agent

### Changed
- Switched all agents to Sonnet 4.6
- Simplified peer-review skills (52% line count reduction)
- Codebase-snapshot agent runs fully lights-out (no Bash)

### Fixed
- Removed unsupported `-a never` flag from `codex exec`
- Removed unsupported `-o` flag from `codex exec resume`
- Eliminated compound Bash commands that trigger approval prompts
- Replaced polling bash script with individual `gh api` calls
- Banned `$()` substitution and `jq` piping to avoid approval prompts

## [0.2.0] - 2025-02-08

### Added
- macOS/Linux and Windows install instructions with hard links
- Cross-platform `.review/` directory for temp files (replaces system temp)
- Minimum 2 review rounds before convergence

### Changed
- Inherit Codex model from `~/.codex/config.toml` instead of hardcoding
- Use Read/Write tools instead of `cp` for file operations
- Generate session IDs natively (no Bash dependency)
- Use `codex -C` flag instead of `cd` to avoid approval prompts
- Renamed "adversarial review" to "peer review"

### Fixed
- Cleaned stale references and legacy config dependencies from skill and agent files

## [0.1.0] - 2025-02-01

### Added
- `/peer-review-code` skill — multi-agent code review with counter-review and convergence loop
- `/peer-review-plan` skill — iterative plan review between Claude and Codex CLI
- `/merge` skill — squash-merge a PR and update project docs
- `codebase-snapshot` agent — capture point-in-time architecture and metrics
- `code-cleanup-analyst` agent — identify dead code and unused imports
- `code-simplifier` agent — simplify code for clarity and maintainability
- `CLAUDE.md` with project conventions and hard link setup
- README with install instructions and key patterns documentation
