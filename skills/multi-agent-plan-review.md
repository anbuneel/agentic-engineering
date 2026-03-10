---
name: multi-agent-plan-review
description: >
  Send an implementation plan to Codex CLI for multi-agent review, with
  Claude performing counter-review on each finding. Use when the user
  wants a second opinion on a plan, asks to review a plan with another
  model, or says "have Codex review this plan", "get feedback on my
  plan", or "multi-agent plan review". Best used during or after plan mode.
---

# Multi-Agent Plan Review (Iterative with Counter-Review)

Send the current implementation plan to OpenAI Codex CLI for multi-agent review. Claude performs a **counter-review** on each round of Codex feedback — assigning dispositions (agree/partial/defer/reject) to every finding before revising. When Claude rejects a finding, the **user breaks the tie**. Min 2 rounds, max 5.

## When to Invoke

- When the user runs `/multi-agent-plan-review` during or after plan mode
- When the user wants a second opinion on a plan from a different model

## Agent Instructions

### Step 1: Setup

1. Detect the project root:
   ```bash
   git rev-parse --show-toplevel
   ```
   Store as `PROJECT_ROOT`. **Bash safety rules for the entire skill:**
   - **Never use `cd`** — use `-C "${PROJECT_ROOT}"` and absolute paths
   - **Never use `$()`** command substitution — run commands standalone, parse output natively
   - **Never pipe to `jq`** — parse JSON natively in-context
2. Generate a random 8-character hex string natively (not Bash). Store as `REVIEW_ID`.
3. Set `REVIEW_DIR` to `.review/` in the project root (absolute path). Add `.review/` to `.gitignore` if missing. The directory is created automatically when the Write tool writes the first file into it — do NOT use `mkdir`.
4. Initialize state file `${REVIEW_DIR}/plan-review-state-${REVIEW_ID}.json` tracking: `reviewId`, `round` (starts at 1), `codexThreadId` (starts as null), `planFile`, `findings`, `dispositions`.

   **CRITICAL — Read and update this state file after every major step to guard against context compression. After compaction, the state file is the ONLY reliable source of truth. Always re-read it before acting.**

5. Read the plan file with the **Read** tool, write it to `${REVIEW_DIR}/claude-plan-${REVIEW_ID}.md` with the **Write** tool. If no plan exists in context, ask the user.

### Step 2: Codex Review (Round 1)

```bash
codex exec --json \
  -s read-only \
  -C "${PROJECT_ROOT}" \
  "Review this plan thoroughly: ${REVIEW_DIR}/claude-plan-${REVIEW_ID}.md

End with exactly: VERDICT: APPROVED or VERDICT: REVISE"
```

The `--json` flag outputs structured JSONL. The first line is always `{"type":"thread.started","thread_id":"<UUID>"}`. Parse `thread_id` and save as `codexThreadId` in the state file immediately — this survives context compaction. Extract review content from `item.completed` events (the `text` field) and write to `${REVIEW_DIR}/codex-review-${REVIEW_ID}.md`.

### Step 3: Read Review & Check Verdict

**At the start of EVERY round, read the state file and restore all variables** (`REVIEW_ID`, `REVIEW_DIR`, `PROJECT_ROOT`, `codexThreadId`, `round`). After context compaction these values exist ONLY in the state file.

1. Extract the review content from the JSONL output (`item.completed` events, `text` field). Write to `${REVIEW_DIR}/codex-review-round-${ROUND}-${REVIEW_ID}.md`.
2. Check verdict:
   - **Minimum 2 rounds required** — never exit before Round 2
   - Round ≥ 2 AND **VERDICT: APPROVED** → go to Step 7 (Done)
   - **VERDICT: REVISE** → go to Step 4 (Counter-Review)
   - Round ≥ 2 AND no actionable items → treat as approved
   - Max rounds (5) → go to Step 7 with warning

### Step 4: Counter-Review

Critically evaluate **every** Codex finding and assign a disposition:

| Disposition | Meaning | Action |
|-------------|---------|--------|
| **agree** | Codex is right | Revise the plan |
| **partial** | Valid but scope down | Revise with reduced scope |
| **defer** | Valid but not now | Log for later |
| **reject** | Disagree | Must include rationale |

Present the counter-review table to the user:

```
## Counter-Review — Round N

| # | Codex Finding | Disposition | Rationale |
|---|--------------|-------------|-----------|
| 1 | [summary] | agree | [why] |
| 2 | [summary] | reject | [counter-argument] |
```

### Step 5: Decision Gate

If there are **reject** or **defer** dispositions, present each to the user with both sides' arguments. Wait for their call on each item. If user sides with Codex → move to `agree`. If user confirms defer → keep as `defer`.

If no reject/defer items, skip this step.

### Step 6: Revise & Re-submit

1. Apply all `agree` and `partial` findings. Skip `reject` (user-confirmed) and `defer`.
2. Rewrite `${REVIEW_DIR}/claude-plan-${REVIEW_ID}.md`.
3. Summarize to the user: what changed, what's deferred, what's rejected.
4. Resume the Codex session using the `codexThreadId` from the state file:

```bash
codex exec resume "${CODEX_THREAD_ID}" --json "I've revised the plan. Updated plan: ${REVIEW_DIR}/claude-plan-${REVIEW_ID}.md. [Changes made. Findings not addressed with rationale.] Re-review. VERDICT: APPROVED or VERDICT: REVISE"
```

Extract review content from `item.completed` events as in Round 1.

**If resume fails**, fall back to fresh `codex exec --json -s read-only -C "${PROJECT_ROOT}"` with prior round context. Capture the new `thread_id` and update state.

5. Increment `round` in the state file. Go back to **Step 3**.

### Step 7: Write Review Artifact

Write the full review transcript to `docs/reviews/plan-review-${REVIEW_ID}.md`. Create `docs/reviews/` if needed.

Include these sections:
- **Metadata** — review ID, date, model, status (approved / max rounds), plan file path
- **Summary metrics** — rounds, findings by disposition (agreed, partial, deferred, rejected)
- **Each round** — full Codex feedback, full counter-review table, user decisions on disputes, revisions applied
- **Final plan** — complete text after all revisions
- **Deferred items** — cumulative across all rounds
- **Rejected items** — user-confirmed, with rationale

**Important:** Full audit trail — complete Codex feedback and counter-review tables, not summaries.

### Step 8: Present Final Result

Present status (approved or max rounds), link to artifact, summary metrics, and any remaining concerns or deferred items.

### Step 9: Cleanup

Delete `.review/` and its contents: `rm -rf "${REVIEW_DIR}"` (single Bash command, permission prompt expected).

## Rules

- Claude **critically evaluates** Codex feedback — counter-review, not compliance
- Every finding MUST get a disposition — no silent skipping
- `reject` dispositions MUST go through the user decision gate
- Codex model inherited from `~/.codex/config.toml` — do not hardcode `-m`
- Always use `-s read-only` — Codex should never write files
- Minimum 2 rounds, max 5
- If Codex CLI missing, suggest `npm install -g @openai/codex`
- If a revision contradicts user's explicit requirements, flag as `reject`
- Use Read/Write tools for file operations — never `cp`, `mv`, or shell redirects
- **Never use `cd` in Bash** — use `-C <dir>` for codex/git, `--repo` for gh
- **Never use `$()` or pipe to `jq`** — run standalone, parse JSON natively
