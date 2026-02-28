# Changelog

All notable changes to this project are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/).

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
- Removed `.paira/config.json` dependency from peer-review-code
- Cleaned stale references from agent files

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
