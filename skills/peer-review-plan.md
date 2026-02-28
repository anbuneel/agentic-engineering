# Peer Review Plan (Iterative with Counter-Review)

Send the current implementation plan to OpenAI Codex CLI for peer review. Claude performs a **counter-review** on each round of Codex feedback — assigning dispositions (agree/partial/defer/reject) to every finding before revising. When Claude rejects a finding, the **user breaks the tie**. Min 2 rounds, max 5.

## When to Invoke

- When the user runs `/peer-review-plan` during or after plan mode
- When the user wants a second opinion on a plan from a different model

## Agent Instructions

### Step 1: Setup

1. Generate a random 8-character hex string natively (not Bash). Store as `REVIEW_ID`.
2. Set `REVIEW_DIR` to `.review/` in the project root (absolute path). Add `.review/` to `.gitignore` if missing. The directory is created automatically when the Write tool writes the first file into it — do NOT use `mkdir`.
3. Read the plan file with the **Read** tool, write it to `${REVIEW_DIR}/claude-plan-${REVIEW_ID}.md` with the **Write** tool. If no plan exists in context, ask the user.

### Step 2: Codex Review (Round 1)

```bash
codex exec \
  -s read-only \
  -o "${REVIEW_DIR}/codex-review-${REVIEW_ID}.md" \
  "Review this plan thoroughly: ${REVIEW_DIR}/claude-plan-${REVIEW_ID}.md

End with exactly: VERDICT: APPROVED or VERDICT: REVISE"
```

Capture the `session id: <uuid>` from output. Store as `CODEX_SESSION_ID`.

### Step 3: Read Review & Check Verdict

1. Read the Codex output file (or stdout for resume rounds).
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
4. Resume the Codex session:

```bash
codex exec resume "${CODEX_SESSION_ID}" "I've revised the plan. Updated plan: ${REVIEW_DIR}/claude-plan-${REVIEW_ID}.md. [Changes made. Findings not addressed with rationale.] Re-review. VERDICT: APPROVED or VERDICT: REVISE"
```

Resume output goes to stdout — capture from Bash tool result.

**If resume fails**, fall back to fresh `codex exec -s read-only -o "${REVIEW_DIR}/codex-round-${ROUND}-${REVIEW_ID}.md"` with prior round context.

Go back to **Step 3**.

### Step 7: Write Review Artifact

Write the full review transcript to `docs/reviews/plan-review-{REVIEW_ID}.md`. Create `docs/reviews/` if needed.

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

Delete all files in `.review/` using the agent's file tools (not `rm`).

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
