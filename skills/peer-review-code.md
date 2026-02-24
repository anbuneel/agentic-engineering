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
git rev-parse --is-inside-work-tree
```
```bash
git status --porcelain
```
- Non-empty → stop: "Working tree is not clean. Commit or stash changes first."

```bash
git rev-parse --abbrev-ref HEAD
```
- `main` or `master` → stop: "Switch to a feature branch."

```bash
gh auth status
```
```bash
codex --version
```

Generate a random 8-character hex string natively (not Bash). Store as `REVIEW_ID`.

Set `REVIEW_DIR` to `.review/` in the project root (absolute path). Add `.review/` to `.gitignore` if missing. The directory is created automatically when the Write tool writes the first file into it — do NOT use `mkdir`.

Initialize state file `${REVIEW_DIR}/review-state-${REVIEW_ID}.json` tracking: reviewId, round, codexSessionId, nextCodexCommand, prNumber, seenCommentIds, findings, dispositions, rebasedThisRound.

**CRITICAL — Read and update this state file after every major step to guard against context compression. After compaction, the state file is the ONLY reliable source of truth for variables like `CODEX_SESSION_ID`, `round`, and `nextCodexCommand`. Always re-read it before acting.**

---

### Step 0b: Code Simplification

Launch **code-simplifier** agent (`code-simplifier:code-simplifier`): "Simplify and refine all changes on the current branch compared to the base branch. Focus on clarity, consistency, and maintainability while preserving exact functionality."

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

Guard empty commits — `git diff --quiet` first. If changes exist, `git add` then `git commit` as separate commands.

Update state file.

---

### Step 2: Create PR

```bash
gh pr view --json number
```

- PR exists → capture number, reuse.
- No PR → push branch, write PR body to `${REVIEW_DIR}/pr-body-${REVIEW_ID}.md`, create with `gh pr create --body-file`, capture number.

Update state file.

---

## Phase B: Review Loop

Loop for up to 5 rounds.

**CRITICAL — At the start of EVERY round, read the state file NOW and restore all variables from it** (`REVIEW_ID`, `REVIEW_DIR`, `CODEX_SESSION_ID`, `nextCodexCommand`, `PR_NUMBER`, `round`, `seenCommentIds`). After context compaction these values exist ONLY in the state file. Set `rebasedThisRound: false`.

### Step 2a: Wait Remote

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

Track seen IDs with namespace prefixes (`issues:{id}`, `reviews:{id}`, `pull_comments:{id}`). Repeat until new comments arrive or timeout (8 minutes). Save to state file.

### Step 2b: Codex Review

**CRITICAL — Read the state file BEFORE choosing which command to run.** Check `nextCodexCommand` and `codexSessionId`. If `nextCodexCommand` exists in state, use it verbatim (it is a resume command). If it is missing or null, this is Round 1 — use fresh exec. **Using fresh `codex exec` on round 2+ is a bug.**

**Round 1** (no `nextCodexCommand` in state):
```bash
codex exec -s read-only -o "${REVIEW_DIR}/codex-review-${REVIEW_ID}.md" "Review all changes on this branch compared to ${BASE_BRANCH}. Focus on bugs, security issues, code quality, and edge cases. Number each finding with severity (MUST FIX / SHOULD FIX / CONSIDER). End with VERDICT: APPROVED or VERDICT: REVISE"
```

Capture `CODEX_SESSION_ID` from output. Build the next round's resume command and save BOTH to state file:
```json
{
  "codexSessionId": "<captured ID>",
  "nextCodexCommand": "codex exec resume \"<captured ID>\" \"Code has been updated. [PLACEHOLDER_FOR_CHANGE_SUMMARY]. Re-review all changes compared to ${BASE_BRANCH}. Focus on whether previous findings are resolved and any new issues. VERDICT: APPROVED or VERDICT: REVISE\""
}
```

**Round 2+** (`nextCodexCommand` exists in state):

Read `nextCodexCommand` from state file. Replace `[PLACEHOLDER_FOR_CHANGE_SUMMARY]` with a summary of fixes made this round. Run the resulting command. Resume output goes to stdout — capture from Bash tool result.

After running, update `nextCodexCommand` in state file with the same session ID for the next potential round.

**If resume fails**, fall back to fresh `codex exec -s read-only -o "${REVIEW_DIR}/codex-review-${REVIEW_ID}.md"` with prior round context. Update state to clear `nextCodexCommand` and capture new session ID.

### Step 2c: Consolidate

Extract findings from all sources (remote comments + Codex output). For each: file, line, severity, description, source agent. Deduplicate using `file:severity:keywords` fingerprints. Update state file.

### Step 2d: Counter-Review

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

### Step 2e: Check Convergence

**Note:** Convergence is checked AFTER Step 2d (counter-review) but BEFORE Step 2f (fix). The `fixesMadeThisRound` flag refers to whether Step 2f will produce commits — i.e., whether there are `agree` or `partial` dispositions from this round's counter-review.

- **Minimum 2 rounds required** — never exit before Round 2
- **If fixes will be made this round** (any `agree` or `partial` dispositions) → **not converged** — a verification round is needed after every fix
- Round ≥ 2 AND no fixes this round AND all MUST FIX resolved AND no net new findings → **converged**
- Round ≥ 2 AND no fixes this round AND Codex APPROVED AND no unresolved MUST FIX → **converged**
- Max rounds → exit with warning

### Step 2f: Fix

Fix all `agree` and `partial` findings using Edit/Write tools.

**Commit MUST FIX first** (safe checkpoint). Run quality gates (each as a separate command). If pass and changes exist, commit `"fix: round ${ROUND} must-fix findings"`. Store SHA.

**Then SHOULD FIX.** Run quality gates. If fail → revert to checkpoint (`git clean -fd`, `git checkout <sha> -- .` as separate commands), defer all SHOULD FIX. If pass and changes exist, commit `"fix: round ${ROUND} should-fix findings"`.

Update state file after each commit.

### Step 2g: Post Round Summary

Write summary to `${REVIEW_DIR}/round-summary-${REVIEW_ID}.md`, post:

```bash
gh api "repos/{owner}/{repo}/issues/${PR_NUMBER}/comments" -F "body=@${REVIEW_DIR}/round-summary-${REVIEW_ID}.md"
```

### Step 2h: Rebase Check

```bash
git fetch origin "${BASE_BRANCH}"
```
```bash
git merge-base HEAD "origin/${BASE_BRANCH}"
```

If base moved: rebase, abort+notify on conflict, run gates if success. Set `rebasedThisRound` in state.

### Step 2i: Push

If rebased: `git push --force-with-lease origin "${BRANCH}"`. Otherwise: `git push origin "${BRANCH}"`.

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

5. **Cleanup:** `rm -rf .review/`

### Step 4: Present Final Result

Present status (converged or max rounds), PR link, artifact link, summary metrics, and any remaining concerns or deferred items.

---

## Rules

- Claude **critically evaluates** all feedback — counter-review, not compliance
- Every finding MUST get a disposition — no silent skipping
- `reject` dispositions MUST go through the user decision gate
- MUST FIX committed BEFORE SHOULD FIX (safe rollback checkpoint)
- Quality gates after every fix batch — never skip
- Guard empty commits: `git diff --quiet` before committing
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
