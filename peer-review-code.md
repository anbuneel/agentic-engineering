# Peer Review Code (Multi-Agent with Counter-Review)

Orchestrate an automated code review across multiple AI agents (Codex CLI, GitHub-connected bots) with Claude as the central coordinator. Claude performs a **counter-review** on every finding — assigning dispositions (agree/partial/defer/reject) before fixing. When Claude rejects a finding, the **user breaks the tie**. Max 5 rounds.

## When to Invoke

- When the user runs `/peer-review-code` on a feature branch
- When the user wants multi-agent code review with automated fixes

## Prerequisites

The following must be set up **before** running this skill:

### Local Tools
- **Git** — installed and configured
- **GitHub CLI (`gh`)** — installed and authenticated (`gh auth login`)
- **Codex CLI** — installed (`npm install -g @openai/codex`)

### GitHub Remote Agents

The review loop polls the PR for comments from remote agents. For agents to respond automatically, they must be installed on the GitHub repo:

1. **Claude bot** — Install the [Claude GitHub App](https://github.com/apps/claude) on your repo. It will automatically review new PRs.
2. **Devin** — Install the [Devin GitHub App](https://github.com/apps/devin-ai-integration) on your repo. Assign Devin as a reviewer or configure auto-review in Devin's dashboard.
3. **Codex GH Connector** — Install the [OpenAI Codex GitHub App](https://github.com/apps/openai-codex) on your repo. It will automatically review new PRs.

**Note:** All three are optional. The Wait Remote step will poll for whatever agents respond within the timeout. If none respond, the round continues with just the local Codex CLI review. The more agents installed, the more diverse the feedback.

---

## Agent Instructions

When invoked, execute the following phases sequentially.

---

## Phase A: Pre-Loop (runs once)

### Step 0: Preflight

Run ALL of these checks. If any fail, stop and tell the user what's wrong.

```bash
git rev-parse --is-inside-work-tree
```
```bash
git status --porcelain
```
- If output is non-empty, stop: "Working tree is not clean. Commit or stash changes first."

```bash
git rev-parse --abbrev-ref HEAD
```
- If branch is `main` or `master`, stop: "Cannot review the main branch. Switch to a feature branch."

```bash
gh auth status
```
```bash
codex --version
```

Generate a session ID:
```bash
REVIEW_ID=$(python -c "import uuid; print(str(uuid.uuid4())[:8])")
```

Resolve the cross-platform temp directory:
```bash
TEMP_DIR=$(python -c "import tempfile; print(tempfile.gettempdir())")
```

Store the branch name, REVIEW_ID, and TEMP_DIR for the rest of the session.

### Config Loading

Read `.paira/config.json` from the project root if it exists. Use these defaults for any missing fields:

| Key | Default |
|-----|---------|
| `baseBranch` | `"main"` |
| `maxRounds` | `5` |
| `qualityGates` | `["lint", "typecheck", "test", "build"]` |
| Quality gate commands | `npm run lint`, `npx tsc --noEmit`, `npm test`, `npm run build` |
| `pollTimeoutMin` | `8` |
| `approvalMode` | `"prompt"` |

**Config Trust Gate:** If `.paira/config.json` specifies quality gate commands that differ from the defaults above, present ALL non-default commands to the user for confirmation before executing any of them. This prevents arbitrary command execution from untrusted configs.

### Initialize State File

Write the initial state to `${TEMP_DIR}/paira-state-${REVIEW_ID}.json`:

```json
{
  "reviewId": "<REVIEW_ID>",
  "round": 0,
  "codexSessionId": null,
  "prNumber": null,
  "seenCommentIds": [],
  "findings": [],
  "dispositions": [],
  "rebasedThisRound": false
}
```

Read and update this state file after every major step to guard against context compression.

---

### Step 1: Pre-Review (Claude runs natively)

Use the Task tool to launch pr-review-toolkit agents in parallel:

1. **code-reviewer** — `pr-review-toolkit:code-reviewer`
2. **silent-failure-hunter** — `pr-review-toolkit:silent-failure-hunter`
3. **type-design-analyzer** — `pr-review-toolkit:type-design-analyzer`

Prompt each agent: "Review all unstaged and staged changes on the current branch compared to the base branch. Report findings with severity (MUST FIX / SHOULD FIX / CONSIDER) and specific file:line references."

#### Counter-Review (Pre-Review)

Evaluate every finding from the agents. Assign dispositions:

| Disposition | Meaning | Action |
|-------------|---------|--------|
| **agree** | Valid, will fix | Fix it now |
| **partial** | Valid but scoped down | Fix the core issue, note what's deferred |
| **defer** | Valid but not now | Log it for later |
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

If there are any **reject** or **defer** dispositions, present them to the user:

```
### Disputed Findings

[For each reject:]
1. **[Finding summary]**
   - Agent says: [argument]
   - Claude says: [counter-argument]
   - **Your call: side with agent (fix) or Claude (skip)?**

### Deferred Findings

[For each defer:]
2. **[Finding summary]**
   - Agent says: [argument]
   - Claude says: [why deferring]
   - **OK to defer, or override to fix now?**
```

Wait for user response on each item. For rejects: if user sides with the agent, move to `agree`. For defers: if user overrides, move to `agree` (fix now).

If there are no `reject` or `defer` items, skip this step.

#### Fix Pre-Review Findings

Fix all `agree` and `partial` findings directly using Edit/Write tools. Do NOT spawn subprocesses.

Run quality gates:
```bash
npm run lint && npx tsc --noEmit && npm test && npm run build
```

If gates fail after fixing: stop and notify the user.

Guard empty commits — check before committing:
```bash
git diff --quiet
```
- If exit code 0 (no changes), skip the commit.
- If changes exist: `git add <specific changed files> && git commit -m "fix: pre-review fixes (paira)"`

Update the state file.

---

### Step 2: Create PR

Check if a PR already exists for this branch:
```bash
gh pr view --json number 2>/dev/null
```

- If PR exists: capture the PR number, reuse it.
- If no PR:
  1. Push the branch:
     ```bash
     git push -u origin "${BRANCH}"
     ```
  2. Write PR body to temp file: `${TEMP_DIR}/pr-body-${REVIEW_ID}.md`
  3. Create PR:
     ```bash
     gh pr create --title "..." --body-file "${TEMP_DIR}/pr-body-${REVIEW_ID}.md"
     ```
  4. Capture PR number from output.

Update the state file with `prNumber`.

---

## Phase B: Review Loop

Loop for up to `maxRounds` rounds. At the **start of each round**, read the state file and set `rebasedThisRound: false`.

### Step 2a: Wait Remote

Poll ALL three GitHub comment endpoints for new comments. Use the owner/repo from `gh repo view --json owner,name`:

```bash
gh api "repos/{owner}/{repo}/issues/${PR_NUMBER}/comments"
gh api "repos/{owner}/{repo}/pulls/${PR_NUMBER}/reviews"
gh api "repos/{owner}/{repo}/pulls/${PR_NUMBER}/comments"
```

Track seen comment IDs with namespace prefixes to avoid cross-endpoint collisions:
- `issues:{id}` — issue-level comments
- `reviews:{id}` — PR review bodies
- `pull_comments:{id}` — inline review comments

Load seen IDs from the state file. Poll every ~30 seconds until:
- New comments arrive from at least one agent, OR
- Timeout after `pollTimeoutMin` minutes

Save new seen IDs to the state file. Note which agents responded.

### Step 2b: Codex Review

**Round 1:**
```bash
codex exec -m gpt-5.3-codex -s read-only -o "${TEMP_DIR}/codex-review-${REVIEW_ID}.md" "Review all changes on this branch compared to ${BASE_BRANCH}. Focus on bugs, security issues, code quality, and edge cases. Number each finding with severity (MUST FIX / SHOULD FIX / CONSIDER). End with VERDICT: APPROVED or VERDICT: REVISE"
```

Capture `CODEX_SESSION_ID` from the output line that says `session id: <uuid>`. Save to state file.

**Round 2+:**
```bash
codex exec resume "${CODEX_SESSION_ID}" "Code has been updated. [summary of changes since last round]. Re-review all changes compared to ${BASE_BRANCH}. Focus on whether previous findings are resolved and any new issues. VERDICT: APPROVED or VERDICT: REVISE" > "${TEMP_DIR}/codex-round-${ROUND}-${REVIEW_ID}.md" 2>&1
```

Read the FULL output file — do NOT truncate with `tail` or `head`.

**Note:** If `codex exec resume` fails (session expired or sandbox not inherited), fall back to a fresh `codex exec -s read-only` with context about prior rounds in the prompt.

### Step 2c: Consolidate

Read ALL collected inputs:
- Remote comments from all three endpoints (only new ones)
- Codex output from the round file (full, not truncated)

Claude parses the findings natively — no deterministic parser needed. For each finding, extract:
- **File** and line reference
- **Severity** (MUST FIX / SHOULD FIX / CONSIDER)
- **Description** of the issue
- **Source agent**

Deduplicate across agents using fingerprints: `file:severity:keywords`. Check against existing findings in the state file.

Update the state file with new findings.

### Step 2d: Counter-Review

Evaluate every NEW finding. Assign dispositions (agree/partial/defer/reject).

Present the counter-review table to the user:

```
## Counter-Review — Round N

| # | Agent | Finding | Severity | Disposition | Rationale |
|---|-------|---------|----------|-------------|-----------|
| 1 | codex | [summary] | MUST FIX | agree | [why] |
| 2 | gh-claude | [summary] | SHOULD FIX | reject | [why wrong] |
```

#### Decision Gate

If there are any **reject** or **defer** dispositions, present them to the user:

```
### Disputed Findings

[For each reject:]
1. **[Finding summary]**
   - Agent says: [argument]
   - Claude says: [counter-argument]
   - **Your call: side with agent (fix) or Claude (skip)?**

### Deferred Findings

[For each defer:]
2. **[Finding summary]**
   - Agent says: [argument]
   - Claude says: [why deferring]
   - **OK to defer, or override to fix now?**
```

Wait for user response on each item. For rejects: if user sides with the agent, move to `agree`. For defers: if user overrides, move to `agree` (fix now).

If there are no `reject` or `defer` items, skip this step.

Update dispositions in state file.

### Step 2e: Check Convergence

Read the state file. Count findings by status:
- If ALL `MUST FIX` findings are resolved AND no net new findings this round → **converged**, exit loop
- If Codex verdict is `APPROVED` AND no unresolved `MUST FIX` → **converged**, exit loop
- If max rounds reached → exit loop with warning

### Step 2f: Fix

Fix all `agree` and `partial` findings using Edit/Write tools directly.

**Commit ordering for safe rollback:**

1. **Fix MUST FIX findings first.** Run quality gates. If gates pass:
   ```bash
   git diff --quiet || (git add <specific files> && git commit -m "fix: round ${ROUND} must-fix findings (paira)")
   ```
   This commit is the **safe checkpoint**. Store the SHA.

2. **Fix SHOULD FIX findings.** Run quality gates. If gates FAIL:
   - Revert cleanly to the MUST FIX checkpoint:
     ```bash
     git clean -fd && git checkout <must-fix-sha> -- .
     ```
   - Move all SHOULD FIX findings to DEFER in the state file.
   - Skip the SHOULD FIX commit.

3. If SHOULD FIX gates PASS:
   ```bash
   git diff --quiet || (git add <specific files> && git commit -m "fix: round ${ROUND} should-fix findings (paira)")
   ```

Update state file after each commit.

### Step 2g: Post Round Summary

Write the round summary to a temp file, then post to the PR:

```bash
gh api "repos/{owner}/{repo}/issues/${PR_NUMBER}/comments" -F "body=@${TEMP_DIR}/round-summary-${REVIEW_ID}.md"
```

Using `-F body=@file` avoids shell injection from generated content.

### Step 2h: Rebase Check

```bash
git fetch origin "${BASE_BRANCH}"
```

Compare the merge-base to detect if the base branch has moved:
```bash
git merge-base HEAD "origin/${BASE_BRANCH}"
```

- If base has NOT moved → skip (keep `rebasedThisRound: false`)
- If base moved:
  1. Attempt rebase:
     ```bash
     git rebase "origin/${BASE_BRANCH}"
     ```
  2. If conflict:
     ```bash
     git rebase --abort
     ```
     Then stop and notify user: "Rebase conflict detected. Please resolve manually."
  3. If rebase succeeded: run quality gates
  4. If gates fail: stop and notify user
  5. If gates pass: set `rebasedThisRound: true` in state file

### Step 2i: Push

```bash
# If rebased this round, use force-with-lease
git push --force-with-lease origin "${BRANCH}"

# Otherwise, normal push
git push origin "${BRANCH}"
```

Update state file.

---

**(End of loop — go back to Step 2a for the next round)**

---

## Phase C: Post-Loop (runs once)

### Step 3: Finalize

#### Create GitHub Issues for Deferred Items

For each finding with disposition `defer`, create a GitHub issue:
```bash
gh issue create --title "..." --body-file "${TEMP_DIR}/defer-issue-${REVIEW_ID}.md"
```

Write the issue body to a temp file first to avoid shell injection.

#### Update PR Description

Write the final PR body to a temp file, then:
```bash
gh pr edit "${PR_NUMBER}" --body-file "${TEMP_DIR}/pr-final-body-${REVIEW_ID}.md"
```

#### Post Final Summary Comment

Write summary to temp file, post via:
```bash
gh api "repos/{owner}/{repo}/issues/${PR_NUMBER}/comments" -F "body=@${TEMP_DIR}/final-summary-${REVIEW_ID}.md"
```

#### Write Review Artifact

Write the full review transcript to `docs/reviews/code-review-${REVIEW_ID}.md` in the current repo.

**Note:** Review the artifact content before committing — remove any sensitive data from raw agent outputs.

The artifact should follow this structure:

```markdown
# Code Review: {branch}

**Review ID:** {REVIEW_ID}
**Date:** [date]
**PR:** #{prNumber}
**Status:** [Converged after N rounds | Max rounds reached]

## Summary
| Metric | Count |
|--------|-------|
| Rounds | N |
| Total findings | X |
| Agreed & fixed | X |
| Partially fixed | X |
| Deferred | X |
| Rejected | X |

## Pre-Review
[Pre-review findings, counter-review, fixes applied]

## Round 1
### Remote Agent Comments
[Comments from GitHub-connected agents — from all three endpoints]
### Codex Review
[Full Codex feedback]
### Counter-Review
[Disposition table]
### User Decisions
[Rejected finding resolutions]
### Fixes Applied
[What was changed]

## Round 2
[Same structure]

## Deferred Items
[Cumulative list — these became GitHub issues]

## Rejected Items
[User-confirmed skips with rationale]
```

If `docs/reviews/` does not exist, create it.

#### Cleanup Temp Files

```bash
python -c "import glob, os, tempfile; [os.remove(f) for f in glob.glob(os.path.join(tempfile.gettempdir(), f'*-${REVIEW_ID}*'))]"
```

### Step 4: Present Final Result

**If converged:**
```
## Code Review Complete

**Status:** Converged after N round(s)
**PR:** #[number]
**Artifact:** docs/reviews/code-review-{REVIEW_ID}.md

### Review Summary
- Rounds: N
- Total findings: X
- Agreed & fixed: X
- Partially fixed: X
- Deferred: X (GitHub issues created)
- Rejected: X

The code has been reviewed by multiple agents and counter-reviewed by Claude. All MUST FIX findings resolved.
```

**If max rounds reached:**
```
## Code Review Complete

**Status:** Max rounds (5) reached — not fully converged
**PR:** #[number]
**Artifact:** docs/reviews/code-review-{REVIEW_ID}.md

### Remaining Concerns
[List unresolved MUST FIX findings]

### Deferred Items
[Cumulative list — GitHub issues created]

Review did not fully converge. Check remaining concerns before merging.
```

---

## Rules

- Claude **critically evaluates** all agent feedback before fixing — this is counter-review, not compliance
- Every finding MUST get a disposition — no silent skipping
- `reject` dispositions MUST go through the user decision gate — Claude cannot unilaterally ignore feedback
- MUST FIX findings are always committed BEFORE SHOULD FIX (safe rollback checkpoint)
- Quality gates run after every fix batch — never skip
- Guard empty commits: always check `git diff --quiet` before committing
- All bash variables MUST be quoted: `"${VAR}"` not `${VAR}`
- PR bodies and comment bodies MUST use temp files with `-F body=@file` — never inline generated content in shell commands
- State file MUST be read and updated after every major step
- Default Codex model is `gpt-5.3-codex`. Accept model override from user arguments
- Always use read-only sandbox (`-s read-only`) for Codex — it should never write files
- Max 5 review rounds to prevent infinite loops
- If Codex CLI is not installed or fails, inform the user and suggest `npm install -g @openai/codex`
- If `gh auth status` fails, inform the user and suggest `gh auth login`
- Claude fixes code directly via Edit/Write tools — NEVER spawn `claude -p` or any Claude subprocess
