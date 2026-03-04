# Peer Review Code (Multi-Agent with Counter-Review)

Orchestrate an automated code review across multiple AI agents (Codex CLI, GitHub-connected bots) with Claude as the central coordinator. Claude performs a **counter-review** on every finding — assigning dispositions (agree/partial/defer/reject) before fixing. When Claude rejects a finding, the **user breaks the tie**. Min 2 rounds, max 5.

## When to Invoke

- When the user runs `/peer-review-code` on a feature branch
- When the user wants multi-agent code review with automated fixes

## Prerequisites

Requires **git**, **gh** (authenticated), and **codex CLI**. For remote agent reviews (Claude bot, Devin, Codex GH), install their GitHub Apps on your repo — see README for setup.

---

## Agent Instructions

When invoked, execute the following phases sequentially.

---

## Phase A: Pre-Loop (runs once)

### Step 0: Preflight

Run ALL checks — stop if any fail:

```bash
git rev-parse --is-inside-work-tree && git rev-parse --show-toplevel
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

Set `REVIEW_DIR` to `.review/` in the project root (absolute path). Add `.review/` to `.gitignore` if missing. The directory is created automatically when the Write tool writes the first file into it — do NOT use `mkdir`.

Initialize state file `${REVIEW_DIR}/review-state-${REVIEW_ID}.json` tracking: reviewId, round, branch, baseBranch, codexSessionId, nextCodexCommand, prNumber, seenCommentIds, findings, dispositions, rebasedThisRound, ghBotFindings.

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

**CRITICAL — Read and update this state file after every major step to guard against context compression. After compaction, the state file is the ONLY reliable source of truth for variables like `CODEX_SESSION_ID`, `round`, and `nextCodexCommand`. Always re-read it before acting.**

---

### Step 0b: Code Simplification

Check the diff size first:

```bash
git -C "${PROJECT_ROOT}" diff --stat "${BASE_BRANCH}"...HEAD
```

Count the total lines changed natively. If < 20 lines changed, skip this step with a note: "Skipping simplification pass (diff < 20 lines)."

Otherwise, run the built-in `/simplify` skill to review changed code for reuse, quality, and efficiency.

If changes made: run quality gates (lint, typecheck, test, build — each as a separate command). If pass, commit `"refactor: code simplification pass"`. If fail, revert and notify user.

---

### Step 1: Pre-Review (Claude runs natively)

Launch pr-review-toolkit agents in parallel:

1. `pr-review-toolkit:code-reviewer`
2. `pr-review-toolkit:silent-failure-hunter`
3. `pr-review-toolkit:type-design-analyzer`

Prompt each: "Review all changes on the current branch compared to the base branch. Report findings with severity (MUST FIX / SHOULD FIX / CONSIDER) and file:line references."

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

Fix all `agree` and `partial` findings using Edit/Write tools.

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

**CRITICAL — At the start of EVERY round, read the state file NOW and restore all variables from it** (`REVIEW_ID`, `REVIEW_DIR`, `BRANCH`, `BASE_BRANCH`, `CODEX_SESSION_ID`, `nextCodexCommand`, `PR_NUMBER`, `round`, `seenCommentIds`). After context compaction these values exist ONLY in the state file. Set `rebasedThisRound: false`.

### Step 2a: Parallel Review (Codex + GH Bots)

**CRITICAL — Launch BOTH tasks below simultaneously in a SINGLE message using parallel tool calls. Do NOT run them sequentially. Do NOT wait for one to finish before starting the other. They have zero dependency on each other.**

**Task 1: Codex Review** — run as a background Bash command (`run_in_background: true`).

**CRITICAL — Read the state file BEFORE choosing which command to run.** Check `nextCodexCommand` and `codexSessionId`. If `nextCodexCommand` exists in state, use it verbatim (it is a resume command). If it is missing or null, this is Round 1 — use fresh exec. **Using fresh `codex exec` on round 2+ is a bug.**

**Round 1** (no `nextCodexCommand` in state):
```bash
codex exec -s read-only -C "${PROJECT_ROOT}" -o "${REVIEW_DIR}/codex-review-${REVIEW_ID}.md" "Review all changes on this branch compared to ${BASE_BRANCH}. Focus on bugs, security issues, code quality, and edge cases. Number each finding with severity (MUST FIX / SHOULD FIX / CONSIDER). End with VERDICT: APPROVED or VERDICT: REVISE"
```

Capture `CODEX_SESSION_ID` from output. Build the next round's resume command and save BOTH to state file:
```json
{
  "codexSessionId": "<captured ID>",
  "nextCodexCommand": "codex exec resume \"<captured ID>\" -C \"${PROJECT_ROOT}\" \"Code has been updated. [PLACEHOLDER_FOR_CHANGE_SUMMARY]. Re-review all changes compared to ${BASE_BRANCH}. Focus on whether previous findings are resolved and any new issues. VERDICT: APPROVED or VERDICT: REVISE\""
}
```

**Round 2+** (`nextCodexCommand` exists in state):

Read `nextCodexCommand` from state file. Replace `[PLACEHOLDER_FOR_CHANGE_SUMMARY]` with a summary of fixes made this round. Run the resulting command. Resume output goes to stdout — capture from Bash tool result.

After running, update `nextCodexCommand` in state file with the same session ID for the next potential round.

**If resume fails**, fall back to fresh `codex exec -s read-only -C "${PROJECT_ROOT}" -o "${REVIEW_DIR}/codex-review-${REVIEW_ID}.md"` with prior round context. Update state to clear `nextCodexCommand` and capture new session ID.

**Task 2: GH Bot Polling** — run in parallel with Task 1 (launch in the same message).

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

Track seen IDs with namespace prefixes (`issues:{id}`, `reviews:{id}`, `pull_comments:{id}`). Repeat until new comments arrive or timeout. **Adaptive timeout:** Round 1 = 8 minutes (bots may need to initialize); Round 2+ = 4 minutes (bots already warmed up). Save to state file.

#### Sync Point

Wait for **both** Task 1 and Task 2 to complete before proceeding. Collect Codex output and GH bot comments.

### Step 2b: Consolidate

Extract findings from all sources (remote comments + Codex output). For each: file, line, severity, description, source agent. Deduplicate using `file:severity:keywords` fingerprints.

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
- Round ≥ 2 AND no fixes this round AND all MUST FIX resolved AND no net new findings AND **all fixed GH bot findings `verified: true`** → **converged**
- Round ≥ 2 AND no fixes this round AND Codex APPROVED AND no unresolved MUST FIX AND **all fixed GH bot findings `verified: true`** → **converged**
- Max rounds → exit with warning

### Step 2e: Fix

Fix all `agree` and `partial` findings using Edit/Write tools.

**Commit MUST FIX first** (safe checkpoint). Run quality gates (each as a separate command). If pass and changes exist, commit `"fix: round ${ROUND} must-fix findings"`. Store SHA.

**Then SHOULD FIX.** Run quality gates. If fail → revert to checkpoint (`git -C "${PROJECT_ROOT}" checkout <sha> -- .` to restore tracked files), defer all SHOULD FIX. If pass and changes exist, commit `"fix: round ${ROUND} should-fix findings"`.

After each commit, update `ghBotFindings` — for every GH bot finding fixed this round, set `roundFixed` to the current round and `verified` to `null` (pending verification next poll).

Update state file after each commit.

### Step 2f: Post Round Summary

Write summary to `${REVIEW_DIR}/round-summary-${REVIEW_ID}.md`, post:

```bash
gh api "repos/{owner}/{repo}/issues/${PR_NUMBER}/comments" -F "body=@${REVIEW_DIR}/round-summary-${REVIEW_ID}.md"
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

   Include: review metadata (ID, date, PR, status), summary metrics, pre-review findings + counter-review, each round's remote comments + Codex feedback + counter-review + user decisions + fixes, cumulative deferred items (with issue links), rejected items with rationale.

   **Full audit trail** — complete feedback and tables, not summaries. Review for sensitive data before committing.

5. **Cleanup:** Delete `.review/` and its contents: `rm -rf "${REVIEW_DIR}"` (single Bash command, permission prompt expected).

### Step 4: Present Final Result

Present status (converged or max rounds), PR link, artifact link, summary metrics, and any remaining concerns or deferred items.

---

## Rules

- Claude **critically evaluates** all feedback — counter-review, not compliance
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
- Minimum 2 rounds, max 5
- If Codex CLI missing, suggest `npm install -g @openai/codex`
- If `gh auth status` fails, suggest `gh auth login`
- Fix code via Edit/Write tools — NEVER spawn `claude -p` or Claude subprocess
- **Never use `cd` in Bash** — use `-C <dir>` for codex/git, `--repo` for gh
- **Never use `$()` or pipe to `jq`** — run standalone, parse JSON natively
