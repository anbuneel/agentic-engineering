# Design Philosophy

## Why This Exists

AI coding assistants are powerful, but ad-hoc prompting doesn't scale. You end up repeating the same review instructions, forgetting edge cases, and getting inconsistent results across sessions. These skills codify workflows that I run daily — turning them into repeatable, debuggable processes.

## Prompts Deserve the Same Rigor as Code

These markdown files have error handling, state management, convergence criteria, and rollback logic — not because it's over-engineering, but because without it, multi-agent workflows silently fail in ways you don't notice until production.

Specific patterns that came from hitting real failure modes:

- **State file persistence** — Context compression can wipe all variables mid-review. The state file is the single source of truth that survives compaction. Every major step reads and updates it.
- **MUST FIX before SHOULD FIX** — Commit ordering matters. MUST FIX findings get committed first as a safe checkpoint. If SHOULD FIX changes break quality gates, the agent reverts to that checkpoint instead of losing critical fixes.
- **Codex session resume with fallback** — Codex CLI sessions can be resumed to maintain context across rounds. If resume fails (session expired, format changed), the skill falls back to a fresh exec with prior round context injected.
- **Quality gates after every fix batch** — Never skip. Lint, typecheck, test, build — each as a separate command so failures are attributable.

## The Counter-Review Pattern

The counter-review pattern came from a specific frustration: AI agents blindly apply every piece of feedback they receive, even when it's wrong.

Having Claude assign dispositions (agree/partial/defer/reject) to each finding — and requiring the human to break ties on rejections — means nothing is silently applied and nothing is silently ignored.

This creates an audit trail: every finding from every reviewer is documented with its disposition, rationale, and outcome. The review artifact captures the full decision history, not just the final diff.

## Why Markdown Instead of Code

An earlier attempt as a TypeScript CLI hit a fundamental blocker: you can't easily nest one AI agent session inside another. Markdown instruction files sidestep that entirely — the agent *is* the runtime, and the skill is just a set of instructions it follows. No build step, no dependency management, no version conflicts.

This also makes the skills transparent. You can read exactly what the agent will do before running it. There's no compiled binary, no abstraction layer — just instructions.

## Cross-Platform Discipline

Every design decision is informed by running these skills daily on Windows:

- **No `cd` in Bash** — Use `-C <dir>` for codex/git, `--repo` for gh
- **No `$()` or pipe to `jq`** — Run commands standalone, parse JSON natively
- **No shell redirects** — Use Read/Write tools for all file operations
- **No `rm`** — Use agent file tools for cleanup
- **`.review/` in project root** — Not system temp dirs, which vary by OS and trigger permission prompts
- **Session IDs generated natively** — No dependency on `uuidgen`, `openssl`, or other shell tools
