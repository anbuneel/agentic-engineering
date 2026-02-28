# Changelog

All notable changes to this project are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/).

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
