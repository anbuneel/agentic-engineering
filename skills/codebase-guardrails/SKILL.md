---
name: codebase-guardrails
description: >
  Audit a codebase for what makes agent-written changes go wrong (several
  ways of doing the same thing, weak types, missing boundaries, gaps in
  checks and tests) and write a plan that fixes each problem at the most
  deterministic layer: code first, then static checks, then prose. On a new
  app, sets the baseline before agents write much code. Use when the user
  asks to evaluate code organization, find refactoring opportunities, do
  housekeeping, make a codebase easier for agents to change, says
  "guardrails audit" or "agent-ready audit", or is starting a new app built
  with agents. Reports only; never changes source code.
---

# Codebase Guardrails

Agents copy what already exists and take the shortest path. In a codebase built mostly by agents, the main risk is drift: several ways of doing the same thing, types that allow invalid states, and rules that live only in prose. Each new agent copies whichever variant it reads first.

This skill finds those problems and plans a fix for each at the highest layer that works:

| Layer | What it is |
|---|---|
| `CODE` | A structural change that removes the problem class: one shared schema, a branded type, one wrapper, a deleted alternative |
| `CHECK` | A compiler flag, lint rule, boundary rule, test, CI step, or hook that fails when the problem returns |
| `PROSE` | A line in an agent instruction file, a comment, or a skill. Only when `CODE` and `CHECK` cannot work |
| `REVIEW` | A decision only a person should make: conventions, boundaries, the example files agents copy |

Most items should be `CODE` plus a `CHECK` that keeps them fixed. The skill reads code and runs read-only tools. It writes a report and nothing else.

## When to Invoke

- `/codebase-guardrails` (Claude Code plugin: `/ae:codebase-guardrails`; Codex: `$codebase-guardrails`)
- Before a cleanup push on a codebase built mostly by agents
- At the start of a new app, before agents write most of the code
- Periodically, to catch new drift. A re-run puts its tool counts next to the last report's.

## Prerequisites

Requires **git**. The analysis tools are optional: the skill runs what the project already has and records the rest as skipped. Stack references:

- [references/node-typescript.md](references/node-typescript.md): tool commands, patterns, and the new-app baseline for Node, TypeScript, Fastify, and web frontends
- [references/other-stacks.md](references/other-stacks.md): equivalents for Python, Java and Kotlin, Go, and .NET

## Options

- `mode=<auto|existing|new>` — default `auto`, which picks `new` when the scope has fewer than 30 source files, else `existing`.
- `scope=<path>` — default the repo root. Limits the audit to one app or package.
- `tools=<installed|fetch>` — default `installed`, which never downloads anything. `fetch` also runs missing Node tools through `npx --yes <tool>`, which uses the npx cache and does not change `package.json` or the lockfile.
- `lenses=<off|on>` — default `off`. `on` adds the `type-design-analyzer` and `silent-failure-hunter` passes after the tools run.

Print the resolved options at startup.

## Runtime

The steps are the same in Claude Code, Codex, and GitHub Copilot. Use the agent's own file, search, and shell tools.

Shell rules for the whole skill:

- Never use `cd`. Use `git -C`, tool flags, and absolute paths.
- Never use `$()` or pipes to `jq`. Run commands standalone and parse output natively.
- Never use shell redirects. Use the tool's own output-file flag, or read stdout and write it with the file-write tool.

## Agent Instructions

### Step 1: Setup

1. Run `git rev-parse --show-toplevel` and store it as `PROJECT_ROOT`. If it fails, stop: "Not a git repository."
2. Generate an 8-character hex `RUN_ID` natively.
3. Set `REVIEW_DIR` to `${PROJECT_ROOT}/.review/`. Add `.review/` to `.gitignore` if missing, before any tool runs, so tools like knip skip it.
4. Resolve `SCOPE` to an absolute path inside `PROJECT_ROOT`.

### Step 2: Detect

1. Detect languages, frameworks, package manager, monorepo layout, test runner, and CI from the manifest and config files. Read the matching stack reference.
2. Count source files under `SCOPE`, excluding generated, vendored, and build output. Resolve `mode=auto`.
3. Read the agent instruction files: `CLAUDE.md`, `AGENTS.md`, `.github/copilot-instructions.md`, `.github/instructions/*.instructions.md`, `CONTRIBUTING.md`, project skills, and agent hook config. Note the conventions they claim.
4. If an earlier `docs/analysis/codebase-guardrails-*.md` exists, read its tool counts.

### Step 3: Run the tools

Run the tools listed in the stack reference before reading code for opinions. In `mode=new`, run only the compiler, the linter, and the tests.

- Run from `PROJECT_ROOT` against `SCOPE`. Save output under `REVIEW_DIR` with `RUN_ID` in the file name.
- A non-zero exit that reports findings is a success. A crash or config error is `failed: <first error line>`; move on and do not debug the project's tool setup.
- For each stricter compiler flag the project does not use yet, run the compiler once with that flag and record the error count. That count is the cost of turning the flag on.
- Keep counts per rule and per directory plus a few examples. Do not paste full output into the report.

Record each tool as `ran`, `skipped: <reason>`, or `failed: <reason>`.

### Step 4: Map conventions

For each concern that applies, list every way the code does it, with up to three example paths and an approximate count. Name one canonical way, the reason, and the example file agents should copy.

Concerns: route or module definition, input validation and where request and response types come from, where business logic lives, data access, errors, config and env vars, auth checks, logging, frontend data fetching, frontend state, types shared between client and server, and tests.

Pick by most type-safe, then most used, then simplest. When two variants are close, make it a `REVIEW` item instead of deciding. In `mode=new`, record the intended way from the stack reference and mark it `missing` if no example exists yet.

### Step 5: Find problems

**`mode=existing`.** Report only problems with evidence: `file:line` or a tool output. Group instances that share a cause into one finding with a count. Look for:

- Duplicate implementations: utilities, wrappers, constants, types. Watch for `v2`, `new`, `old`, `legacy`, and `utils` next to `helpers`.
- Types defined in more than one place that can drift, especially client against server
- Escape hatches (`any`, unchecked casts, non-null assertions, suppression comments), grouped by cause
- States the types allow but the code must never reach: string status fields, raw string IDs that can be swapped, optional fields that are always set together
- Boundary leaks: handlers calling the database, frontend importing server code, import cycles
- Large files, or modules with mixed responsibilities
- Dead code, unused exports, unused dependencies
- Defensive code that hides bugs: defaults on values that should never be missing, catch blocks that return a default, swallowed errors, missing `await`
- Tests that cannot fail, skipped tests, and routes or business logic with no tests
- The verification path: can an agent install, start the app, seed data, and run the tests with one documented command each?
- The feedback loop: do typecheck, lint, and tests run in CI on every PR, in a git hook, and in an agent hook?

If something might be deliberate, put it under Questions for the owner instead.

**`mode=new`.** Mark each item of the stack reference's baseline `present`, `partial`, or `missing`, with the file that shows it.

### Step 6: Lens passes (only with `lenses=on`)

Run after Step 3, so the lenses can use the tool output. In Claude Code, dispatch the `type-design-analyzer` and `silent-failure-hunter` agents with this prompt. Elsewhere, or if the agents are not installed, run each as a separate focused pass yourself.

```text
Review the codebase under ${SCOPE} in the repository at ${PROJECT_ROOT}. Tool output is in ${REVIEW_DIR}. Report patterns, not single instances: group findings by cause, with the number of places and up to three file:line examples. Ignore generated, vendored, and build output. Severity scale: MUST_FIX, SHOULD_FIX, CONSIDER. Return at most 15 findings as a table: severity, cause, count, examples, detail. Do not modify files.
```

Check each lens finding against the code before merging it into Step 5. Record how many you dropped.

### Step 7: Audit the prose

Classify every rule in the instruction files:

- `enforceable`: a check could enforce it. Plan the check, then delete the line.
- `stale`: the code contradicts it. Say whether the code or the line is wrong.
- `keep`: needs judgment, or explains intent.
- `missing`: a convention from Step 4 that no file states. Add a pointer to the example file.

If several instruction files overlap, plan one source file and a way to keep the rest in sync. The target is short: intent, where the example files are, how to verify a change, and rules no check can enforce.

### Step 8: Classify and rank

Give each finding a layer and a fix:

- `CODE`: the files and the end state, plus the `CHECK` that keeps it fixed, or why none exists
- `CHECK`: the exact flag, rule, or config, and today's violation count when known
- `PROSE`: why `CODE` and `CHECK` cannot work
- `REVIEW`: what the owner must decide

Rate effort (`S`/`M`/`L`), risk of breaking behavior (`low`/`med`/`high`), and leverage (`low`/`med`/`high`: how many future agent mistakes it prevents; high for patterns agents copy often and for trust boundaries). Rank by leverage, then effort, then risk.

### Step 9: Plan

Group the items into phases of small PRs. Each PR passes CI on its own and keeps behavior unchanged unless the item says otherwise.

- Phase 1 sets up the feedback loop: CI on every PR, a git hook, an agent hook where the agent has one, and the checks that already pass.
- Roll out each new check in three steps: warning or baseline of existing violations, fix in batches, then error.
- Delete dead code and duplicate variants before adding abstractions. Never plan a rewrite or a framework change.
- Write each PR as a task prompt a fresh agent session can run: goal, files, the check and its rollout step, how to verify, and what done looks like.

In `mode=new`, the plan is the missing and partial baseline items, ending with one complete vertical slice for agents to copy.

### Step 10: Report

Write `docs/analysis/codebase-guardrails-${RUN_ID}.md` following [references/report-template.md](references/report-template.md). Then show the report path, the top 10, the skipped tools, and the questions for the owner, and suggest:

1. Review the canonical choices and `REVIEW` items yourself. Agents copy these the most.
2. Have a model from a different family critique the report: `/ae:multi-agent-plan-review` where installed, otherwise a new chat with the other model.
3. Run the PR prompts one at a time, and review each PR with a model from a different family than the one that wrote it.
4. Re-run this skill after the last phase to compare counts.

## Rules

- Read-only. Write only the report and files under `.review/`, plus the `.review/` line in `.gitignore`. Never install packages or change lockfiles.
- Every finding cites `file:line` or a tool output. Mark guesses as guesses.
- Group instances by cause. Skip anything a formatter fixes.
- Prefer `CODE` over `CHECK` over `PROSE`.
- Never put secret values in the report; name the file and line only.
- Use the agent's file tools for file operations, never `cp`, `mv`, or shell redirects.
