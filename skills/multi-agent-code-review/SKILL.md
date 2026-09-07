---
name: multi-agent-code-review
description: >
  Orchestrate agent-agnostic multi-agent code review across native subagents,
  external CLI reviewers, and GitHub review agents, with the primary driver
  counter-reviewing every finding. Use when the
  user wants code reviewed by multiple AI agents, asks for multi-agent
  code review, multi-model code review, or automated review on a feature
  branch. Also use for "review my PR", "get feedback on my code from
  other models", or "run code review with multiple agents".
---

# Multi-Agent Code Review (Agent-Agnostic with Counter-Review)

Orchestrate an automated code review across multiple AI reviewers with the **primary driver** as coordinator. The primary driver is whichever agent is executing this skill: Claude Code, Codex App, or Codex CLI. It performs a **counter-review** on every finding, assigning dispositions (agree/partial/defer/reject) before fixing. Rejected and deferred findings are never silently dropped: they are recorded with both sides' arguments and handed to the user at the end under "Needs your call". The loop never blocks on the user.

Round 1 fans out to every reviewer. A verification round runs only when the previous round committed fixes, and only re-engages the reviewers whose findings were acted on. A clean round 1 converges immediately. Maximum 5 rounds.

## When to Invoke

- When the user runs `/multi-agent-code-review` on a feature branch
- When the user wants multi-agent code review with automated fixes

## Prerequisites

Requires **git** and **gh** (authenticated). Reviewers are discovered dynamically:

- Lens agents: `code-reviewer`, `silent-failure-hunter`, `type-design-analyzer`, shipped with this plugin
- Cross-family CLI reviewer: Codex CLI under Claude primary, Claude CLI under Codex primary
- GitHub review agents: Claude bot, OpenAI Codex GitHub app, Devin, or any PR review bot

Missing reviewers never block the workflow unless the user explicitly required that reviewer; record skipped reviewers in the artifact. Under Codex primary, launching `claude` requires a sandbox and approval policy that permits the subprocess and its network access; if policy blocks it, record `skipped: policy` and continue.

---

## Options

- `effort=<fast|balanced|deep>` — default `balanced`. Maps to reasoning effort only; every driver inherits the user's configured model.
- `model=<fable|opus|sonnet|haiku>` — Claude model override for the lens agents and the Claude reviewer channel.
- `budget=<usd>` — per-run `--max-budget-usd` for the Claude reviewer channel. No cap by default.
- `decisions=<deferred|interactive>` — default `deferred`. Deferred never blocks the loop: reject and defer dispositions are recorded and presented at the end. Interactive asks the user mid-loop.
- `require=<codex|claude|gh:<bot>>` — make a reviewer required. Default: none required, all advisory.

The mapping table, override rules, and cost notes are in [references/reviewer-contracts.md](references/reviewer-contracts.md). Print the resolved options at startup.

---

## Runtime Adapter

At startup, identify and store:

- `PRIMARY_DRIVER`: `claude-code`, `codex-app`, `codex-cli`, or `unknown`
- `PRIMARY_CAPABILITIES`: shell, file read/write, native subagents, parallel calls, background commands
- `REVIEWER_REGISTRY`: reviewer entries with `id`, `kind`, `status`, `commandOrAdapter`, and `independence`

Detect `PRIMARY_DRIVER` from the active runtime:

| Signal | Primary driver |
|--------|----------------|
| Claude Code command context, or tools such as Agent/Read/Write/Bash | `claude-code` |
| Codex desktop/app context | `codex-app` |
| Running under `codex exec` / Codex CLI | `codex-cli` |
| Ambiguous runtime | `unknown`; use neutral capabilities and ask only if behavior materially differs |

Use these driver mappings:

| Neutral action | Claude Code | Codex App / CLI |
|---|---|---|
| Read file | Read tool | native file read/edit tool |
| Write/edit file | Write/Edit tools | native apply/edit tool |
| Search files | Glob/Grep tools | `rg` or native search |
| Shell command | Bash tool | shell command tool |
| Native subagent | Agent tool | Codex subagent/custom agent if available |
| Parallel work | parallel tool calls, background shell for long runs | parallel tool calls if available; otherwise sequential with status noted |

Do not spawn a subprocess of the same primary driver to perform the fixes. External CLI reviewers are read-only reviewers.

## Reviewer Registry

Always include `primary-native`: the primary driver's own review pass.

Add available reviewers:

- `lens:code-reviewer`, `lens:silent-failure-hunter`, `lens:type-design-analyzer` — independence `native` under Claude, `primary-native` when run as passes under Codex
- `codex-cli` when Claude is primary and Codex CLI is available; under Codex primary, skip by default unless the user requested it, and label `secondary same-family review` if run
- `claude-cli` when Codex is primary and Claude CLI is available; under Claude primary, skip by default unless the user requested it, and label `secondary same-family review` if run
- `gh:<bot>` for every GitHub review agent that comments on the PR, regardless of primary driver

Registry entries record `status` (`ran`, `skipped: <reason>`, `failed: <reason>`), `independence` (`independent`, `native`, `primary-native`, `secondary same-family`), and per round whether the reviewer was engaged.

## External Reviewer Command Contracts

The invocation, resume, output parsing, read-only flags, and failure handling for the Claude and Codex reviewer channels are in [references/reviewer-contracts.md](references/reviewer-contracts.md). Every reviewer returns the object defined in [references/findings-schema.md](references/findings-schema.md) with the severity enum `MUST_FIX`, `SHOULD_FIX`, `CONSIDER`. Write that schema to `${REVIEW_DIR}/findings.schema.json` at preflight.

Prompts for this skill, substituted into `[PROMPT]` in the contracts:

**Round 1:**

```text
Repository root: ${PROJECT_ROOT}. Review all changes on this branch compared to ${BASE_BRANCH}. Use read-only commands such as git diff, git status, and file reads. Focus on bugs, security issues, code quality, and edge cases. Report each finding with severity MUST_FIX, SHOULD_FIX, or CONSIDER, the file path relative to the repository root, and the line number. Do not modify files. Return only the findings object.
```

**Verification round (resumed session):**

```text
Repository root: ${PROJECT_ROOT}. Code has been updated. [CHANGE_SUMMARY]. Findings not addressed, with rationale: [REJECTED_AND_DEFERRED]. Re-review all changes compared to ${BASE_BRANCH}. Report whether each previous finding is resolved, and any new findings, using the same severity scale. Do not modify files. Return only the findings object.
```

Lens agent task prompt (round 1): "Review all changes on the current branch compared to `${BASE_BRANCH}` in the repository at `${PROJECT_ROOT}`. Severity scale: MUST_FIX, SHOULD_FIX, CONSIDER. Return the findings object defined by this schema as your final message: [schema JSON]." For a verification round, prefix it with the change summary and the lens's own prior findings, and ask which are resolved.

Output files: `${REVIEW_DIR}/<reviewer>-review-round-${ROUND}-${REVIEW_ID}.json`.

---

## Agent Instructions

Execute the phases in order. **Bash safety rules for the entire skill:**

- **Never use `cd`** — use `git -C "${PROJECT_ROOT}"`, `codex -C`, `gh --repo`, and absolute paths
- **Never use `$()`** command substitution — run commands standalone, parse output natively
- **Never pipe to `jq`** — parse JSON natively in-context
- Run each command as a standalone call; never chain with `&&`, `;`, or `|`

**CRITICAL — the state file is the only source of truth that survives context compaction. Read it at the start of every phase and every round; update it after every major step.**

---

## Phase A: Preflight (runs once)

### Step A1: Repository checks

Run each check as a standalone command and stop on the first failure:

```bash
git rev-parse --is-inside-work-tree
```
```bash
git rev-parse --show-toplevel
```
Store as `PROJECT_ROOT`.

```bash
git -C "${PROJECT_ROOT}" status --porcelain
```
Non-empty → stop: "Working tree is not clean. Commit or stash changes first."

```bash
git -C "${PROJECT_ROOT}" rev-parse --abbrev-ref HEAD
```
Store as `BRANCH`.

```bash
gh repo view --json defaultBranchRef,nameWithOwner
```
Parse natively. Store the default branch as `BASE_BRANCH` and `nameWithOwner` as `REPO`. If `BRANCH` equals `BASE_BRANCH` → stop: "Switch to a feature branch."

```bash
gh auth status
```
Fails → stop and suggest `gh auth login`.

Check the cross-family reviewer CLI for this driver: `codex --version` under Claude primary, `claude --version` under Codex primary. Missing → registry entry `skipped: not installed`, continue.

### Step A2: Review identity and directory

Generate a random 8-character hex string natively (not Bash). Store as `REVIEW_ID`. Set `REVIEW_DIR` to `${PROJECT_ROOT}/.review/`. Add `.review/` to `.gitignore` if missing. The directory is created by the first file write; do not `mkdir`.

Write the findings schema (severity enum `MUST_FIX`, `SHOULD_FIX`, `CONSIDER`) to `${REVIEW_DIR}/findings.schema.json`.

### Step A3: Quality gates

Resolve the commands that must pass after every fix batch, in this order:

1. A `Quality gates` (or `Quality Gates`) section in the project's `CLAUDE.md` or `AGENTS.md`: use the commands listed there verbatim.
2. Otherwise detect: `package.json` scripts `lint`, `typecheck` (or `tsc`), `test`, `build`, run with the workspace's package manager (`pnpm` when `pnpm-lock.yaml` or `pnpm-workspace.yaml` exists, `yarn` when `yarn.lock`, else `npm run`); a `turbo.json` at the root means run the scripts through the root `package.json`; `pyproject.toml` → `ruff check .` and `pytest` when those tools are configured; `Cargo.toml` → `cargo clippy` and `cargo test`; `go.mod` → `go vet ./...` and `go test ./...`.
3. Nothing found → `qualityGates: []` and a warning in the artifact that fixes were not verified by gates.

Store the list as `qualityGates`. Each gate is run as its own standalone command.

### Step A4: State file

Initialize `${REVIEW_DIR}/review-state-${REVIEW_ID}.json`:

| Field | Purpose |
|-------|---------|
| `reviewId`, `primaryDriver`, `projectRoot`, `reviewDir`, `branch`, `baseBranch`, `repo`, `prNumber` | identity |
| `options` | resolved effort, model, budget, decisions, require |
| `reviewerRegistry` | entries described above |
| `qualityGates` | commands from Step A3 |
| `round` | starts at 1 |
| `externalThreadIds` | `codex`, `claude` session ids |
| `seenCommentIds` | namespaced GitHub comment ids already processed |
| `findings` | every finding with source, fingerprint, round raised, disposition, fix commit |
| `needsYourCall` | reject and defer items with both sides' arguments |
| `engagedThisRound` | reviewer ids launched in the current round |
| `actedOnSources` | reviewer ids whose findings were fixed in the previous round |
| `pushedSinceLastPoll` | whether commits were pushed since the last bot poll |
| `ghBotFindings` | per-bot finding tracking, table below |

`ghBotFindings` entries:

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | `gh-1`, `gh-2`, ... |
| `source` | string | bot name (`claude-bot`, `devin`, `codex-gh`, ...) |
| `fingerprint` | string | from the findings schema rules |
| `summary` | string | short description |
| `roundRaised` | number | round the finding first appeared |
| `roundFixed` | number or null | round the fix was committed |
| `verified` | boolean or null | `true` resolved, `false` re-raised after fix, `null` pending next poll |

### Step A5: Rebase check (once)

```bash
git -C "${PROJECT_ROOT}" fetch origin "${BASE_BRANCH}"
```
```bash
git -C "${PROJECT_ROOT}" merge-base HEAD "origin/${BASE_BRANCH}"
```

If the base moved, rebase; on conflict abort, notify the user, and stop. After a successful rebase run the quality gates. Do not rebase again during the review: a moved base mid-review is reported in the round summary and handled at finalize.

### Step A6: Ensure the PR exists

```bash
gh pr view --json number
```

PR exists → store `prNumber`. Otherwise push with `git -C "${PROJECT_ROOT}" push -u origin "${BRANCH}"`, write the PR body to `${REVIEW_DIR}/pr-body-${REVIEW_ID}.md`, create it with `gh pr create --body-file`, and store the number. If a rebase happened in Step A5 on an existing PR, push with `--force-with-lease` first.

Set `pushedSinceLastPoll: true`. Update the state file.

---

## Phase B: Review rounds

Loop for up to 5 rounds. **At the start of every round, read the state file and restore every variable from it.**

### Step B1: Choose who reviews this round

- **Round 1:** engage every available reviewer: `primary-native`, the three lens agents, the cross-family CLI reviewer, and GitHub bot polling.
- **Verification round (round 2 and later):** engage only the reviewers listed in `actedOnSources` (their findings were fixed last round) plus any reviewer whose previous run failed. Resume CLI sessions with the verification prompt; re-dispatch lens agents with their prior findings and the change summary. Poll GitHub bots only when `pushedSinceLastPoll` is true. `primary-native` always re-checks the diff of last round's fix commits.

Record `engagedThisRound` in the state file.

### Step B2: Launch in parallel

Launch every engaged reviewer and the bot poll together when the runtime supports parallel tool calls or background commands. Claude Code: long-running CLI reviewers as background shell commands, lens agents in one Agent batch, bot polling in the same batch. Codex: the runtime's parallel or background mechanism, else sequential with `parallelism: unavailable` recorded in the registry.

Read the state file before choosing each CLI command: a null id in `externalThreadIds` means the round-1 command, a stored id means the resume command. Store `thread_id` or `session_id` the moment it is known. On resume failure, fall back to the round-1 command with the prior context in the prompt and store the new id.

**GitHub bot polling.** Poll these endpoints every ~30 seconds, each as a standalone command:

```bash
gh api "repos/${REPO}/issues/${PR_NUMBER}/comments"
```
```bash
gh api "repos/${REPO}/pulls/${PR_NUMBER}/reviews"
```
```bash
gh api "repos/${REPO}/pulls/${PR_NUMBER}/comments"
```

Parse each response natively. Track seen ids with namespace prefixes (`issues:<id>`, `reviews:<id>`, `pull_comments:<id>`) in `seenCommentIds`. Stop when new bot comments arrive or on timeout: 8 minutes in round 1, 4 minutes in later rounds. A timeout with no new comments is not an error. After the poll set `pushedSinceLastPoll: false`.

### Step B3: Sync and consolidate

Wait for every engaged reviewer and the poll. Read each output file. Parse GitHub bot comments into the findings shape. Tag each finding with source and independence, compute fingerprints, and deduplicate per [references/findings-schema.md](references/findings-schema.md). Keep the highest severity on a duplicate and note which reviewers agreed.

**GitHub bot verification.** For each new bot finding, match its fingerprint against `ghBotFindings` entries from the same bot with `roundFixed != null` and `verified == null`:

1. Match → `verified: false` (re-raised); treat as a new finding for counter-review.
2. After processing a bot's new comments, every pending finding from that bot that was not re-raised → `verified: true`.
3. A bot that posted nothing this round while `pushedSinceLastPoll` was true at poll start → `verified: true` on all its pending findings (implicit approval).

Add genuinely new bot findings with `roundFixed: null`, `verified: null`. Update the state file.

### Step B4: Counter-review and decisions

Evaluate every new finding and assign a disposition:

| Disposition | Meaning | Action |
|-------------|---------|--------|
| **agree** | Valid, will fix | Fix this round |
| **partial** | Valid but scoped down | Fix the core issue, record the rest as defer |
| **defer** | Valid but not now | Record under Needs your call |
| **reject** | Disagree | Record under Needs your call with rationale |

Present the table:

```
## Counter-Review — Round N

| # | Source | Finding | Severity | Disposition | Rationale |
|---|--------|---------|----------|-------------|-----------|
| 1 | codex-cli | [summary] | MUST_FIX | agree | [why] |
| 2 | gh:claude-bot | [summary] | SHOULD_FIX | reject | [why wrong] |
```

**Decisions.** With `decisions=deferred` (default): append every reject and defer item to `needsYourCall` with the finding, the reviewer's argument, and the primary driver's argument, then continue. Nothing is fixed for them. With `decisions=interactive`: present each reject and defer item with both sides and wait; the user's call becomes the disposition.

Update dispositions in the state file.

### Step B5: Convergence check

Runs after counter-review and before fixes. `fixesThisRound` is true when any finding has disposition `agree` or `partial`.

- `fixesThisRound` → **not converged**; a verification round follows.
- Any `ghBotFindings` entry with `verified: false` → **not converged**.
- Any `ghBotFindings` entry with `verified: null` and `roundFixed != null` → **not converged**; the next round polls bots.
- A required reviewer (`require=`) that has not returned `APPROVED` and was not skipped by user decision → **not converged**.
- Otherwise → **converged**. This includes a clean round 1.
- Round 5 without convergence → exit with a warning.

Converged → Phase C. Otherwise continue to Step B6.

### Step B6: Fix, verify, commit, push

Fix all `agree` and `partial` findings with the primary driver's native edit tools.

1. **MUST_FIX first.** Apply the fixes, run each quality gate as a standalone command. All pass and `git -C "${PROJECT_ROOT}" diff --quiet` reports changes → `git -C "${PROJECT_ROOT}" add -A` then `git -C "${PROJECT_ROOT}" commit -m "fix: round ${ROUND} must-fix findings"`. Store the SHA as the checkpoint. A gate fails → stop and notify the user with the gate output.
2. **SHOULD_FIX and CONSIDER second.** Apply, run gates. Pass → commit `"fix: round ${ROUND} should-fix findings"`. Fail → restore tracked files to the checkpoint with `git -C "${PROJECT_ROOT}" checkout <sha> -- .`, move those findings to `needsYourCall` with the gate output as the reason.

After each commit: set `fixCommit` on the findings it resolved, set `roundFixed` and `verified: null` on the matching `ghBotFindings`, and record each finding's source in `actedOnSources` for the next round.

Push: `git -C "${PROJECT_ROOT}" push origin "${BRANCH}"`. Set `pushedSinceLastPoll: true`.

Write the round summary (findings, dispositions, fixes, commits, reviewers engaged and skipped) to `${REVIEW_DIR}/round-${ROUND}-summary-${REVIEW_ID}.md` and post it:

```bash
gh api "repos/${REPO}/issues/${PR_NUMBER}/comments" -F "body=@${REVIEW_DIR}/round-${ROUND}-summary-${REVIEW_ID}.md"
```

Increment `round`, update the state file, and return to Step B1.

---

## Phase C: Finalize (runs once)

Read the state file.

1. **Needs your call.** Present every item in `needsYourCall` with the finding, both arguments, and the reviewer. This is the one place the user is asked to decide, and nothing waits on the answer.
2. **Deferred items → issues.** For each defer item, write the body to `${REVIEW_DIR}/issue-<n>-${REVIEW_ID}.md` and run `gh issue create --title "..." --body-file <path>`. Record the issue URLs.
3. **Base moved?** If Step A5's base has moved since, report it and offer a rebase; do not rebase silently.
4. **PR description.** Write the body to `${REVIEW_DIR}/pr-final-${REVIEW_ID}.md`, apply with `gh pr edit --body-file`.
5. **Final comment.** Status (converged or max rounds), rounds, findings by disposition, Needs your call, issue links. Post with `gh api ... -F "body=@file"`.
6. **Artifact.** Write `docs/reviews/code-review-${REVIEW_ID}.md`: metadata (id, date, driver, PR, status, options), reviewer registry with independence and per-round engagement, summary metrics, every round's findings, counter-review tables, fixes and commits, GitHub bot verification history, Needs your call with both arguments, deferred items with issue links, and confidence notes for skipped or failed reviewers. Full audit trail, not summaries. Check for sensitive data before writing.

`.review/` is gitignored and every file carries the review id. Leave it in place.

Present the result: status, PR link, artifact path, metrics, and the Needs your call list.

---

## Rules

- Primary driver **critically evaluates** all feedback — counter-review, not compliance
- Every finding gets a disposition; reject and defer are recorded with both sides and surfaced under Needs your call, never dropped
- The loop never waits on the user unless `decisions=interactive`
- Round 1 engages everyone; verification rounds engage only reviewers whose findings were acted on; bots are polled only after a push
- A clean round 1 converges. Every round that commits fixes is followed by a verification round. Max 5 rounds
- MUST_FIX committed before SHOULD_FIX (safe rollback checkpoint); quality gates after every fix batch, each as a standalone command
- Rebase once at preflight; report a moved base afterwards, never rebase mid-review
- Every driver inherits the user's configured model; `effort=` maps to reasoning effort only, `model=` overrides Claude only
- External reviewer commands, flags, output parsing, and resume rules come from `references/reviewer-contracts.md`; every reviewer returns the `references/findings-schema.md` object
- Required reviewers default to none; `require=` makes one required
- Sandbox or network policy blocks on advisory reviewers degrade coverage but do not block convergence
- Fix code with the primary driver's native edit tools; never spawn a subprocess of the primary driver to make changes
- PR, issue, and comment bodies go through files with `--body-file` or `-F body=@file`, never inline
- Guard empty commits with `git -C "${PROJECT_ROOT}" diff --quiet` before committing; quote every variable as `"${VAR}"`
- State file read at the start of every phase and round, updated after every major step
- If Codex CLI is missing or older than the configured model, record the Codex channel as skipped with the reason and suggest `npm install -g @openai/codex`
- If Claude CLI is missing under Codex primary, record it as skipped and continue unless required
- **Never use `cd`, `$()`, `jq` pipes, or command chaining**; never `rm`
