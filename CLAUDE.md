# CLAUDE.md

## Project Overview

Agentic Engineering — a collection of agent-agnostic workflow skills and sub-agents for AI coding agents. Published at <https://github.com/anbuneel/agentic-engineering>.

## Structure

```
skills/          ← Shipped in the ae plugin (/ae:<name> in Claude Code, $<name> in Codex)
  multi-agent-code-review/SKILL.md  (+ references/)
  multi-agent-plan-review/SKILL.md  (+ references/)
  multi-agent-ideate/SKILL.md       (+ references/)
  merge/SKILL.md
extras/skills/   ← In the repo, not in the plugin; installed by copying a directory
  security-scan/SKILL.md
  security-audit/SKILL.md           (+ references/)
  security-posture/SKILL.md
agents/          ← Claude sub-agents shipped in the plugin; Codex runs the lens prompts as passes
  code-reviewer.md, silent-failure-hunter.md, type-design-analyzer.md   ← review lenses
  codebase-snapshot.md, code-cleanup-analyst.md
tools/           ← Standalone CLI tools
  claude-memory-sync/  ← Cross-machine Claude memory sync via git
  codex-setup-sync/    ← Cross-machine Codex setup sync via git
scripts/         ← Dev tooling
  Set-PluginVersion.ps1      ← bump the version in every plugin manifest before a release
.claude-plugin/  ← Claude Code plugin manifest + marketplace (plugin name: ae)
.codex-plugin/   ← Codex plugin manifest
.agents/plugins/ ← Codex marketplace
```

Each skill is `skills/<name>/SKILL.md` per the [Agent Skills specification](https://agentskills.io/specification): the directory name must equal the frontmatter `name`, `description` is required, and reference material belongs in `references/` beside `SKILL.md`. Keep `SKILL.md` under 500 lines.

## Distribution

The repo installs as a plugin named `ae` in both Claude Code and Codex. One install per machine covers every project, every git worktree, and the Codex desktop app. There are no symlinks or copies to keep in sync.

- **Claude Code:** `claude plugin marketplace add anbuneel/agentic-engineering`, then `claude plugin install ae@agentic-engineering`. Skills are invoked as `/ae:<name>`. Cloud sessions never read user-level plugins, so a project that needs them in the cloud declares the marketplace and plugin in its `.claude/settings.json` (shape in the README).
- **Codex:** `codex plugin marketplace add anbuneel/agentic-engineering`, then `codex plugin add ae@agentic-engineering`. Skills are invoked as `$<name>`. Codex cloud does not load plugins.
- **Local development:** `claude --plugin-dir <repo>` loads the working tree and `/reload-plugins` picks up edits. For Codex, add the checkout as a local marketplace with `codex plugin marketplace add <repo>`.
- **Releases:** both tools cache a snapshot and refresh on a version bump. Run `.\scripts\Set-PluginVersion.ps1 -Version x.y.z`, commit, then `claude plugin tag`.
- **Validate before committing:** `claude plugin validate <repo>` checks the manifests, every `SKILL.md`, and agent frontmatter.

## Key Patterns

- **Counter-review**: Agent assigns dispositions (agree/partial/defer/reject) to every finding before acting
- **Needs your call**: reject and defer are recorded with both sides' arguments and presented at the end — nothing silently ignored, and the code review loop never waits on the user (`decisions=interactive` opts back into mid-loop questions)
- **Convergence loop**: round 1 fans out to every reviewer; a verification round runs only after fixes and only for the reviewers whose findings were acted on; a clean round 1 converges; max 5 rounds; GH bot findings confirmed resolved via cross-round fingerprint tracking
- **Reviewer registry**: Multi-agent skills record primary driver, native subagents, external CLI reviewers, common GH review agents, skipped reviewers, and independence notes

## Documentation Rules

- When modifying skill files (`skills/*/SKILL.md`, `extras/skills/*/SKILL.md`), always check and update `docs/SKILLS_GUIDE.md` and `README.md` if the change affects documented behavior, flow diagrams, or step naming
- Only document tracked, shipped skills in README and SKILLS_GUIDE
- `AGENTS.md` is a generated duplicate of `CLAUDE.md` for tools that don't read `CLAUDE.md`. **Edit `CLAUDE.md` only** — `.githooks/pre-commit` regenerates and stages `AGENTS.md` whenever `CLAUDE.md` is staged, rewriting only the H1. Direct edits to `AGENTS.md` will be silently clobbered. Arm hooks once with `git config core.hooksPath .githooks`

## Skill Design Rules

- Every driver inherits the user's configured model. `effort=` maps to reasoning effort only (`--effort` on Claude, `-c model_reasoning_effort` on Codex); `model=<fable|opus|sonnet|haiku>` overrides Claude only; never pass `-m` to Codex
- Reviewer command contracts live in each multi-agent skill's `references/reviewer-contracts.md`, with identical copies across skills — edit them together. The findings schema is in `references/findings-schema.md`
- Claude reviewer channel: `claude -p "<prompt>" --permission-mode plan --permission-prompts none --allowedTools <read-only list> --disallowedTools "Edit" "Write" "MultiEdit" --output-format json --json-schema '<schema>'`; read `structured_output` (or `result` without a schema), store `session_id` as `externalThreadIds.claude`, resume with `--resume`
- Launch Claude CLI reviewer commands with command cwd set to `PROJECT_ROOT`; Claude has no `-C`, so if cwd cannot be set directly, add `--add-dir "${PROJECT_ROOT}"` and include the repo root in the prompt
- The three review lenses (`code-reviewer`, `silent-failure-hunter`, `type-design-analyzer`) ship in `agents/` and are dispatched by name; they are not Claude Code built-ins
- GitHub review agents are common reviewer inputs for all primary drivers
- Same-model secondary sessions are skipped by default unless explicitly requested; if run, label them as secondary same-family review
- External reviewers are advisory by default; a reviewer is required only when explicitly requested by the user
- When Codex is primary, external reviewer subprocesses (`claude`, optional secondary `codex`) require sandbox/approval settings that permit launching those commands and using network-backed model sessions; policy-blocked advisory reviewers are skipped and recorded
- Do NOT use `-a` flag with `codex exec` — it's not supported on the exec subcommand (approvals default to never in non-interactive mode)
- Do NOT use `-s` or `-C` flags with `codex exec resume` — resume only accepts `[SESSION_ID]` and `[PROMPT]` (plus `--json`); sandbox and working directory are inherited from the original session
- Use codex `-C <dir>` instead of `cd` to avoid compound command approval prompts
- Reviewer channels are Claude and Codex only; do not add other model CLIs as reviewers
- Use the primary driver's native file tools for file operations — never `cp`, `mv`, or shell redirects
- Codex CLI: `codex exec --json -s read-only -C <root> --output-schema <schema file> -o <output file> "<prompt>"`; parse `thread_id` from the first JSONL line (`{"type":"thread.started","thread_id":"<UUID>"}`) and read the final message from the `-o` file — never scrape `item.completed`
- Codex CLI older than the configured model fails with "requires a newer version of Codex"; record the channel as skipped and suggest `npm install -g @openai/codex`
- Generate session IDs natively — no Bash calls for setup
- All temp files go in `.review/` inside the project root (gitignored) — avoids permission prompts and is cross-platform

## Writing style

Write in plain, direct language. Lead with what happened and what I need to do. No literary phrasing, no build-up, no flourishes. Keep sentences short.

This applies to everything you write: chat replies, docs, code comments, commit messages, and PR descriptions.
