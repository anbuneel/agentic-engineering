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

Orchestrate an automated code review across multiple AI agents with the **primary driver** as coordinator. The primary driver is whichever agent is executing this skill: Claude Code, Codex App, or Codex CLI. It performs a **counter-review** on every finding — assigning dispositions (agree/partial/defer/reject) before fixing. When the primary driver rejects or defers a finding, the **user breaks the tie**. Min 2 rounds, max 5.

## When to Invoke

- When the user runs `/multi-agent-code-review` on a feature branch
- When the user wants multi-agent code review with automated fixes

## Prerequisites

Requires **git** and **gh** (authenticated). External reviewers are discovered dynamically:

- Native subagents: available inside the current primary driver runtime
- External CLI reviewers: Claude, Codex, and Gemini CLIs when configured
- GitHub review agents: Claude bot, OpenAI Codex GitHub app, Devin, or future PR review bots

GitHub review agents are common reviewer inputs for every primary driver. Missing reviewers never block the workflow unless the user explicitly requested that reviewer; record skipped reviewers in the artifact.

When Codex is the primary driver, external reviewer subprocesses (`claude`, `gemini`, and optional secondary `codex`) require sandbox and approval settings that permit launching those commands and using their network-backed model sessions. If a subprocess is blocked by policy, mark that reviewer as skipped with the policy reason and continue unless the user explicitly required that reviewer.

---

## Options

Use `effort=<fast|balanced|deep>` as the cross-agent option. Map it to the runtime's native model or reasoning controls where available. Default to `balanced`.

Claude Code compatibility: also accept `model=<sonnet|opus|haiku>` for Claude subagent dispatch. If present, store it as `CLAUDE_SUB_AGENT_MODEL`; otherwise choose the runtime default for the selected effort. Print the selected effort and any driver-specific model override.

Effort mapping:

| Effort | Claude-native / Claude CLI | Codex CLI | Reviewer timeouts |
|--------|-----------------------------|-----------|-------------------|
| `fast` | Prefer Haiku when selecting a Claude model; pass `--effort low` when supported | Prefer inherited `~/.codex/config.toml`; if overriding effort, use `-c model_reasoning_effort="low"` | Shortest |
| `balanced` | Prefer Sonnet when selecting a Claude model; pass `--effort medium` when supported | Prefer inherited config; if overriding effort, use `-c model_reasoning_effort="medium"` | Default |
| `deep` | Prefer Opus when selecting a Claude model and the user accepts cost; pass `--effort high` when supported | Prefer inherited config; if overriding effort, use `-c model_reasoning_effort="high"` | Longest |

`model=<sonnet|opus|haiku>` overrides only Claude model selection. Do not hardcode a Codex model with `-m`; Codex model selection is inherited unless the user explicitly requests otherwise.

---

## Runtime Adapter

At startup, identify and store:

- `PRIMARY_DRIVER`: `claude-code`, `codex-app`, `codex-cli`, or `unknown`
- `PRIMARY_CAPABILITIES`: shell, file read/write, native subagents, parallel calls, background commands
- `REVIEWER_REGISTRY`: reviewer entries with `id`, `kind`, `status`, `commandOrAdapter`, and `independence`

Detect `PRIMARY_DRIVER` from the active runtime:

| Signal | Primary driver |
|--------|----------------|
| Claude Code command context, or tools such as Task/Read/Write/Bash | `claude-code` |
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
| Native subagent | Task tool | Codex subagent/custom agent if available |
| Parallel work | parallel tool calls | parallel tool calls if available; otherwise sequential with status noted |

Do not spawn a subprocess for the same primary driver to perform the actual fixes. External CLI reviewers are read-only reviewers.

## Reviewer Registry

Always include:

- `primary-native`: primary driver's own review pass

Add available reviewers:

- `native-code-reviewer`, `native-silent-failure-hunter`, `native-type-design-analyzer` when native subagents are available
- `codex-cli` when Codex CLI is available and the primary driver is not Codex; when Codex is primary, skip by default unless explicitly requested, and label as `secondary same-family review` if run
- `claude-cli` / Claude reviewer channel when Claude CLI is available and the primary driver is Codex; when Claude is primary, skip by default unless explicitly requested, and label as `secondary same-family review` if run
- `gemini-cli` when Gemini CLI is available
- `gh:*` for GitHub review agents discovered on the PR, regardless of primary driver

Same-model secondary sessions are allowed but must be labeled `secondary same-family review` and not treated as fully independent.

Reviewer requirement rules:

- By default, no external reviewer is required; configured reviewers are advisory.
- A reviewer becomes required only when the user explicitly requests it or a skill invocation says it is mandatory.
- If an advisory reviewer is unavailable, skipped, or blocked by sandbox policy, continue and record why.
- If a required reviewer is unavailable, ask the user whether to continue degraded, retry, or stop.
- Any reviewer, required or advisory, can return `VERDICT: REVISE`; the primary driver still counter-reviews each finding before acting.

## External Reviewer Command Contracts

Every external CLI reviewer must be run read-only and must end with exactly one verdict line:

```text
VERDICT: APPROVED
```

or

```text
VERDICT: REVISE
```

For CLI output, write raw reviewer text to `.review/` using the primary driver's file-write capability. Do not use shell redirects.

Claude CLI must be launched with the shell command working directory set to `PROJECT_ROOT`; do not use `cd` to get there. The Claude process has no `-C` equivalent, so if the primary runtime cannot set command cwd directly, add `--add-dir "${PROJECT_ROOT}"` and include `PROJECT_ROOT` in the prompt, but prefer setting cwd so Claude's read-only `git diff` commands run against the right repository.

**Claude CLI, Round 1** (`externalThreadIds.claude` is null in state):

```bash
claude -p "Repository root: ${PROJECT_ROOT}. Review all changes on this branch compared to ${BASE_BRANCH}. Use read-only commands such as git diff, git status, and file reads. Focus on bugs, security issues, code quality, and edge cases. Number each finding with severity (MUST FIX / SHOULD FIX / CONSIDER). Do not modify files. End with exactly: VERDICT: APPROVED or VERDICT: REVISE" --permission-mode plan --allowedTools "Read" "Grep" "Glob" "Bash(git diff:*)" "Bash(git log:*)" "Bash(git status:*)" --disallowedTools "Edit" "Write" "MultiEdit" --output-format json
```

If `model=<sonnet|opus|haiku>` or an effort mapping selects a Claude model, add the matching Claude `--model` option. If effort is configured and the installed Claude CLI supports it, add `--effort low|medium|high`.

Parse the JSON response natively. Store `session_id` as `externalThreadIds.claude` immediately. Extract review text from `result` and write it to `${REVIEW_DIR}/claude-review-${REVIEW_ID}.md`.

**Claude CLI, Round 2+** (`externalThreadIds.claude` exists in state):

```bash
claude -p "Repository root: ${PROJECT_ROOT}. Code has been updated. [CHANGE_SUMMARY]. Re-review all changes compared to ${BASE_BRANCH}. Use read-only commands such as git diff, git status, and file reads. Focus on whether previous findings are resolved and any new issues. Do not modify files. End with exactly: VERDICT: APPROVED or VERDICT: REVISE" --resume "${CLAUDE_SESSION_ID}" --permission-mode plan --allowedTools "Read" "Grep" "Glob" "Bash(git diff:*)" "Bash(git log:*)" "Bash(git status:*)" --disallowedTools "Edit" "Write" "MultiEdit" --output-format json
```

If resume fails, fall back to a fresh Claude CLI review with prior-round context in the prompt, capture the new `session_id`, and update `externalThreadIds.claude`.

**Gemini CLI**:

```bash
gemini -p "Review all changes on this branch compared to ${BASE_BRANCH}. Focus on bugs, security issues, code quality, and edge cases. Number each finding with severity (MUST FIX / SHOULD FIX / CONSIDER). Do NOT modify files. End with exactly: VERDICT: APPROVED or VERDICT: REVISE" -y
```

Capture the shell result and write it to `${REVIEW_DIR}/gemini-review-${REVIEW_ID}.md` with the primary driver's file-write capability.

---

## Agent Instructions

When invoked, execute the following phases sequentially.

---

## Phase A: Pre-Loop (runs once)

### Step 0: Preflight

Run ALL checks — stop if any fail:

```bash
git rev-parse --is-inside-work-tree
```
```bash
git rev-parse --show-toplevel
```

Store the toplevel path as `PROJECT_ROOT`. **Bash safety rules for the entire skill:**
- **Never use `cd`** — use `git -C "${PROJECT_ROOT}"` and absolute paths
- **Never use `$()`** command substitution — run commands standalone, parse output natively
- **Never pipe to `jq`** — parse JSON natively in-context

```bash
git status --porcelain
```
- Non-empty → stop: "Working tree is not clean. Commit or stash changes first."

```bash
git rev-parse --abbrev-ref HEAD
```
Store as `BRANCH`.

Detect the default branch:

```bash
gh repo view --json defaultBranchRef
```
Parse JSON natively to extract the default branch name. Store as `BASE_BRANCH`.

- If `BRANCH` equals `BASE_BRANCH` → stop: "Switch to a feature branch."

```bash
gh auth status
```
```bash
codex --version
```

Generate a random 8-character hex string natively (not Bash). Store as `REVIEW_ID`.

**Detect quality gates** — read `package.json` (or equivalent project config) and identify which of these scripts exist: `lint`, `typecheck`/`tsc`, `test`, `build`. Store the available gate commands in the state file as `qualityGates` (e.g., `["npm run lint", "npm run build"]`). Only these gates run after fix batches — don't fail looking for gates the project doesn't have.

Set `REVIEW_DIR` to `.review/` in the project root (absolute path). Add `.review/` to `.gitignore` if missing. The directory is created automatically when the primary driver's file-write capability writes the first file into it — do NOT use `mkdir`.

Initialize state file `${REVIEW_DIR}/review-state-${REVIEW_ID}.json` tracking: reviewId, primaryDriver, reviewerRegistry, round, branch, baseBranch, externalThreadIds, prNumber, seenCommentIds, findings, dispositions, rebasedThisRound, ghBotFindings.

`ghBotFindings` is an array of objects, each tracking a GH bot finding across rounds:

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique finding ID (e.g., `gh-1`, `gh-2`) |
| `source` | string | Bot name (`claude-bot`, `devin`, `codex-gh`, etc.) |
| `fingerprint` | string | `file:severity:keywords` key for fuzzy matching |
| `summary` | string | Short description of the finding |
| `roundRaised` | number | Round the finding first appeared |
| `roundFixed` | number \| null | Round the fix was committed (`null` if not yet fixed) |
| `verified` | boolean \| null | `true` = resolved, `false` = re-raised after fix, `null` = pending next poll |

**CRITICAL — Read and update this state file after every major step to guard against context compression. After compaction, the state file is the ONLY reliable source of truth for variables like `externalThreadIds`, `round`, and `PR_NUMBER`. Always re-read it before acting.**

---

### Step 0b: Code Simplification

Check the diff size first:

```bash
git -C "${PROJECT_ROOT}" diff --stat "${BASE_BRANCH}"...HEAD
```

Count the total lines changed natively. If < 20 lines changed, skip this step with a note: "Skipping simplification pass (diff < 20 lines)."

Otherwise, run a simplification pass to review changed code for reuse, quality, and efficiency. Claude Code may use the built-in `/simplify` command when available. Codex App, Codex CLI, and other runtimes should run an equivalent inline primary-native simplification pass using the same criteria. If no safe simplification capability is available, skip with a note in the artifact and continue.

If changes made: run quality gates (lint, typecheck, test, build — each as a separate command). If pass, commit `"refactor: code simplification pass"`. If fail, revert and notify user.

---

### Step 1: Pre-Review (Primary Driver + Native Subagents)

Run the primary driver's own review pass and, if native subagents are available, launch these focused review lenses in parallel:

1. code correctness reviewer
2. silent failure hunter
3. type/design analyzer

Prompt each: "Review all changes on the current branch compared to the base branch. Report findings with severity (MUST FIX / SHOULD FIX / CONSIDER) and file:line references."

Claude Code adapter: use the Task tool with `CLAUDE_SUB_AGENT_MODEL` when available.

Codex adapter: use Codex subagents/custom agents when available. If they are not configured, run the three focused lenses as primary-native review passes and mark them as `primary-native` rather than independent subagents.

#### Counter-Review (Pre-Review)

Evaluate every finding. Assign dispositions:

| Disposition | Meaning | Action |
|-------------|---------|--------|
| **agree** | Valid, will fix | Fix it now |
| **partial** | Valid but scoped down | Fix core issue, defer rest |
| **defer** | Valid but not now | Log for later |
| **reject** | Disagree | Must include rationale |

Present the counter-review table to the user:

```
## Pre-Review Counter-Review

| # | Agent | Finding | Disposition | Rationale |
|---|-------|---------|-------------|-----------|
| 1 | code-reviewer | [summary] | agree | [why] |
| 2 | silent-failure-hunter | [summary] | reject | [why wrong] |
```

#### Decision Gate (Pre-Review)

If there are **reject** or **defer** dispositions, present each to the user with both sides' arguments. Wait for their call. If user sides with agent → `agree`. If user confirms defer → keep.

Skip if no reject/defer items.

#### Fix Pre-Review Findings

Fix all `agree` and `partial` findings using the primary driver's native edit/write capabilities.

Run quality gates (lint, typecheck, test, build) — each as a separate command. If any fail, stop and notify user.

Guard empty commits — `git -C "${PROJECT_ROOT}" diff --quiet` first. If changes exist, `git -C "${PROJECT_ROOT}" add` then `git -C "${PROJECT_ROOT}" commit` as separate commands.

Update state file.

---

### Step 2: Create PR

```bash
gh pr view --json number
```

- PR exists → capture number, reuse.
- No PR → `git -C "${PROJECT_ROOT}" push -u origin "${BRANCH}"`, write PR body to `${REVIEW_DIR}/pr-body-${REVIEW_ID}.md`, create with `gh pr create --body-file`, capture number.

Update state file.

---

## Phase B: Review Loop

Loop for up to 5 rounds.

**CRITICAL — At the start of EVERY round, read the state file NOW and restore all variables from it** (`REVIEW_ID`, `REVIEW_DIR`, `BRANCH`, `BASE_BRANCH`, `externalThreadIds`, `PR_NUMBER`, `round`, `seenCommentIds`). After context compaction these values exist ONLY in the state file. Set `rebasedThisRound: false`.

### Step 2a: Parallel Review (External Reviewers + GH Agents)

Launch all available external reviewers and GitHub polling in parallel when the runtime supports parallel tool calls or background commands. If not, run them sequentially and record that limitation in `reviewerRegistry`.

Runtime launch guidance:

- Claude Code: launch long-running CLI reviewers with background shell execution when available (for example `run_in_background: true`), and poll GitHub review agents in the same parallel tool batch.
- Codex App / CLI: use the runtime's available parallel tool calls or background task mechanism. If unavailable, run reviewers sequentially and record `parallelism: unavailable`.
- All runtimes: wait for every launched reviewer and GH polling task at the sync point before consolidating.

**External CLI reviewers** — run every available read-only reviewer from `REVIEWER_REGISTRY`. Advisory reviewers may be skipped if unavailable or policy-blocked. Required reviewers must either run or receive an explicit user decision to continue degraded.

Read the state file BEFORE choosing which command to run. Check `externalThreadIds`.

**Codex CLI, Round 1** (`externalThreadIds.codex` is null in state):
```bash
codex exec --json -s read-only -C "${PROJECT_ROOT}" "Review all changes on this branch compared to ${BASE_BRANCH}. Focus on bugs, security issues, code quality, and edge cases. Number each finding with severity (MUST FIX / SHOULD FIX / CONSIDER). End with exactly: VERDICT: APPROVED or VERDICT: REVISE"
```

The `--json` flag outputs structured JSONL. The **first line** is always `{"type":"thread.started","thread_id":"<UUID>"}`. Parse `thread_id` from this line and save it as `externalThreadIds.codex` in the state file immediately — this is the only reliable way to preserve it across context compaction.

Extract the review content from `item.completed` events in the JSONL output (the `text` field). Write the consolidated review text to `${REVIEW_DIR}/codex-review-${REVIEW_ID}.md`.

**Codex CLI, Round 2+** (`externalThreadIds.codex` exists in state):
```bash
codex exec resume "${CODEX_THREAD_ID}" --json "Code has been updated. [CHANGE_SUMMARY]. Re-review all changes compared to ${BASE_BRANCH}. Focus on whether previous findings are resolved and any new issues. End with exactly: VERDICT: APPROVED or VERDICT: REVISE"
```

Replace `[CHANGE_SUMMARY]` with a summary of fixes made this round. Extract review content from `item.completed` events as in Round 1. The `thread_id` stays the same across resumes — no need to re-capture.

**If resume fails** (e.g., session expired or corrupted), fall back to fresh `codex exec --json` (same as Round 1). Capture the new `thread_id` and update state.

If Codex is the primary driver, label this reviewer as `secondary same-family review`.

**Claude reviewer channel** — when Codex is primary and Claude CLI is configured, run the concrete Claude CLI contract above. Capture `session_id` into `externalThreadIds.claude`, write `result` to `${REVIEW_DIR}/claude-review-${REVIEW_ID}.md`, and resume that session in later rounds with `--resume`. If Claude is primary, skip a second Claude CLI reviewer by default because it is same-family; if the user explicitly requested it, run it and label it `secondary same-family review`. If unavailable or blocked, mark `claude-reviewer` as skipped.

**Gemini CLI** — when available, run a read-only review prompt and write output to `${REVIEW_DIR}/gemini-review-${REVIEW_ID}.md`.

**GH Bot Polling** — run in parallel with CLI reviewers.

Resolve owner/repo once:

```bash
gh repo view --json nameWithOwner
```

Parse JSON natively. Poll these 3 endpoints every ~30 seconds as separate standalone commands:

```bash
gh api repos/{owner}/{repo}/issues/{PR_NUMBER}/comments
```
```bash
gh api repos/{owner}/{repo}/pulls/{PR_NUMBER}/reviews
```
```bash
gh api repos/{owner}/{repo}/pulls/{PR_NUMBER}/comments
```

Parse each endpoint's JSON response natively — do NOT use `grep -c`, `wc -l`, or bash arithmetic to count comments. Extract the array of objects, compare each `id` against `seenCommentIds`, and collect any new ones.

Track seen IDs with namespace prefixes (`issues:{id}`, `reviews:{id}`, `pull_comments:{id}`). Repeat until new comments arrive or timeout. **Adaptive timeout:** Round 1 = 8 minutes (bots may need to initialize); Round 2+ = 4 minutes (bots already warmed up). Save to state file.

If polling times out with no new comments, that's fine — proceed with the available external reviewer output. Always poll in every round regardless of previous results, since bots may respond at different speeds across rounds.

#### Sync Point

Wait for all launched reviewer tasks and GitHub polling to complete before proceeding. Collect external reviewer output and GH bot comments.

### Step 2b: Consolidate

Extract findings from all sources: primary-native review, native subagents, external CLI reviewers, and GitHub review agents. For each: file, line, severity, description, source agent, and independence level. Deduplicate using `file:severity:keywords` fingerprints.

#### GH Bot Finding Verification

After deduplication, cross-reference new GH bot findings against previously-fixed findings in `ghBotFindings`:

1. For each new GH bot finding, compute its `file:severity:keywords` fingerprint.
2. Match against previously-fixed findings (`roundFixed != null`, `verified == null`) from the **same `source` bot**. Use fuzzy matching — same file + overlapping keywords = likely same finding, even if line number shifted.
3. If fingerprint matches a previously-fixed finding → set `verified: false` (re-raised). Treat it as a new finding for counter-review.
4. After processing all new comments from a given bot, any previously-fixed finding from that bot that was **not** re-raised → set `verified: true` (implicitly resolved).
5. If a bot posted **no new comments** this round (polling timed out with no new IDs from that bot) → set `verified: true` on all its pending findings (implicit approval).

Add any genuinely new GH bot findings (no fingerprint match) to `ghBotFindings` with `roundFixed: null`, `verified: null`.

Update state file.

### Step 2c: Counter-Review

Evaluate every NEW finding. Assign dispositions (agree/partial/defer/reject).

Present the counter-review table:

```
## Counter-Review — Round N

| # | Agent | Finding | Severity | Disposition | Rationale |
|---|-------|---------|----------|-------------|-----------|
| 1 | codex | [summary] | MUST FIX | agree | [why] |
| 2 | gh-claude | [summary] | SHOULD FIX | reject | [why wrong] |
```

#### Decision Gate

If there are **reject** or **defer** dispositions, present each to the user with both sides' arguments. Wait for their call. Skip if none.

Update dispositions in state file.

### Step 2d: Check Convergence

**Note:** Convergence is checked AFTER Step 2c (counter-review) but BEFORE Step 2e (fix). The `fixesMadeThisRound` flag refers to whether Step 2e will produce commits — i.e., whether there are `agree` or `partial` dispositions from this round's counter-review.

- **Minimum 2 rounds required** — never exit before Round 2
- **If fixes will be made this round** (any `agree` or `partial` dispositions) → **not converged** — a verification round is needed after every fix
- **If any GH bot finding has `verified: false`** (re-raised after fix) → **not converged** — the re-raised finding must be re-processed through counter-review
- Round >= 2 AND no fixes this round AND all MUST FIX resolved AND no net new findings AND **all fixed GH bot findings `verified: true`** AND all explicitly required reviewers are approved or user-approved skipped -> **converged**
- Round >= 2 AND no fixes this round AND no unresolved MUST FIX AND all reviewer findings have been counter-reviewed AND **all fixed GH bot findings `verified: true`** -> **converged**, even if advisory reviewers were skipped
- Advisory reviewers with no output do not block convergence; document the degraded coverage in confidence notes.
- Max rounds → exit with warning

### Step 2e: Fix

Fix all `agree` and `partial` findings using the primary driver's native edit/write capabilities.

**Commit MUST FIX first** (safe checkpoint). Run quality gates (each as a separate command). If pass and changes exist, commit `"fix: round ${ROUND} must-fix findings"`. Store SHA.

**Then SHOULD FIX.** Run quality gates. If fail → revert to checkpoint (`git -C "${PROJECT_ROOT}" checkout <sha> -- .` to restore tracked files), defer all SHOULD FIX. If pass and changes exist, commit `"fix: round ${ROUND} should-fix findings"`.

After each commit, update `ghBotFindings` — for every GH bot finding fixed this round, set `roundFixed` to the current round and `verified` to `null` (pending verification next poll).

Update state file after each commit.

### Step 2f: Post Round Summary

Write summary to `${REVIEW_DIR}/round-${ROUND}-summary-${REVIEW_ID}.md`, post:

```bash
gh api "repos/{owner}/{repo}/issues/${PR_NUMBER}/comments" -F "body=@${REVIEW_DIR}/round-${ROUND}-summary-${REVIEW_ID}.md"
```

### Step 2g: Rebase Check

```bash
git -C "${PROJECT_ROOT}" fetch origin "${BASE_BRANCH}"
```
```bash
git -C "${PROJECT_ROOT}" merge-base HEAD "origin/${BASE_BRANCH}"
```

If base moved: rebase, abort+notify on conflict, run gates if success. Set `rebasedThisRound` in state.

### Step 2h: Push

If rebased: `git -C "${PROJECT_ROOT}" push --force-with-lease origin "${BRANCH}"` — `--force-with-lease` is safe here because it fails if the remote has commits not in your local copy (e.g., another contributor pushed). If it fails, stop and notify the user instead of retrying. Otherwise: `git -C "${PROJECT_ROOT}" push origin "${BRANCH}"`.

---

**(End of loop — go back to Step 2a for the next round)**

---

## Phase C: Post-Loop (runs once)

### Step 3: Finalize

1. **Deferred items** — create a GitHub issue for each (`gh issue create --body-file`). Write body to temp file first.
2. **Update PR description** — write body to temp file, `gh pr edit --body-file`.
3. **Post final summary comment** — `gh api ... -F "body=@file"`.
4. **Write review artifact** to `docs/reviews/code-review-${REVIEW_ID}.md`. Create dir if needed.

   Include: review metadata (ID, date, primary driver, PR, status), reviewer registry (available, skipped, independence notes), summary metrics, pre-review findings + counter-review, each round's remote comments + external reviewer feedback + counter-review + user decisions + fixes, cumulative deferred items (with issue links), rejected items with rationale, and confidence notes for degraded reviewer coverage.

   **Full audit trail** — complete feedback and tables, not summaries. Review for sensitive data before committing.

5. **Cleanup:** Delete `.review/` and its contents: `rm -rf "${REVIEW_DIR}"` (single Bash command, permission prompt expected).

### Step 4: Present Final Result

Present status (converged or max rounds), PR link, artifact link, summary metrics, and any remaining concerns or deferred items.

---

## Rules

- Primary driver **critically evaluates** all feedback — counter-review, not compliance
- Every finding MUST get a disposition — no silent skipping
- `reject` dispositions MUST go through the user decision gate
- MUST FIX committed BEFORE SHOULD FIX (safe rollback checkpoint)
- Quality gates after every fix batch — never skip
- Guard empty commits: `git -C "${PROJECT_ROOT}" diff --quiet` before committing
- Quote all bash variables: `"${VAR}"`
- PR/comment bodies via temp files with `-F body=@file` — never inline
- State file read/updated after every major step
- Codex model inherited from `~/.codex/config.toml` — do not hardcode `-m`
- Always `-s read-only` for Codex
- Claude CLI reviewer runs with `--permission-mode plan --output-format json`; capture `session_id` and resume with `--resume`
- Launch Claude CLI with command cwd set to `PROJECT_ROOT`; if unavailable, add `--add-dir "${PROJECT_ROOT}"` and include the repo root in the prompt
- Required external reviewers default to none; only user-explicit reviewers are required
- Sandbox or network policy blocks on advisory reviewers degrade coverage but do not block convergence
- Minimum 2 rounds, max 5
- If Codex CLI missing, suggest `npm install -g @openai/codex`
- If Claude reviewer channel is missing while Codex is primary, record it as skipped and continue unless the user explicitly required it
- If `gh auth status` fails, suggest `gh auth login`
- Fix code via the primary driver's native edit tools — never spawn a subprocess of the primary driver to make changes
- **Never use `cd` in Bash** — use `-C <dir>` for codex/git, `--repo` for gh
- **Never use `$()` or pipe to `jq`** — run standalone, parse JSON natively
