# Codex Plan Review (Iterative with Counter-Review)

Send the current implementation plan to OpenAI Codex CLI for adversarial review. Unlike a simple back-and-forth, Claude performs a **counter-review** on each round of Codex feedback — assigning dispositions (agree/partial/defer/reject) to every finding before revising. When Claude rejects a finding, the **user breaks the tie**. Max 5 rounds.

## When to Invoke

- When the user runs `/review-plan` during or after plan mode
- When the user wants a second opinion on a plan from a different model

## Agent Instructions

When invoked, perform the following iterative review loop:

### Step 1: Generate Session ID

Generate a random 8-character hex string natively (do NOT use Bash for this). Store as `REVIEW_ID`.

Resolve the temp directory: on Windows use `$TEMP` or `$TMP` env var, on Linux/macOS use `/tmp`. Store as `TEMP_DIR`.

Use these for all temp file paths: `${TEMP_DIR}/claude-plan-${REVIEW_ID}.md` and `${TEMP_DIR}/codex-review-${REVIEW_ID}.md`.

### Step 2: Capture the Plan

Write the current plan to the session-scoped temporary file.

1. Use the **Read** tool to read the plan file, then use the **Write** tool to write the content to `${TEMP_DIR}/claude-plan-${REVIEW_ID}.md`. Do NOT use `cp` or Bash for file operations — Read/Write tools avoid permission prompts.
2. If there is no plan in the current context, ask the user what they want reviewed

### Step 3: Initial Review (Round 1)

Run Codex CLI in non-interactive, read-only mode:

```bash
codex exec \
  -a never \
  -s read-only \
  -o "${TEMP_DIR}/codex-review-${REVIEW_ID}.md" \
  "Review the implementation plan in ${TEMP_DIR}/claude-plan-${REVIEW_ID}.md. Focus on:
1. Correctness - Will this plan achieve the stated goals?
2. Risks - What could go wrong? Edge cases? Data loss?
3. Missing steps - Is anything forgotten?
4. Alternatives - Is there a simpler or better approach?
5. Security - Any security concerns?

Be specific and actionable. Number each finding clearly (1, 2, 3...).

If the plan is solid and ready to implement, end your review with exactly: VERDICT: APPROVED
If changes are needed, end with exactly: VERDICT: REVISE"
```

**Capture the Codex session ID** from the output line that says `session id: <uuid>`. Store this as `CODEX_SESSION_ID`. You MUST use this exact ID to resume in subsequent rounds (do NOT use `--last`).

**Notes:**
- Codex model and reasoning effort are inherited from `~/.codex/config.toml` — do not hardcode `-m` unless the user overrides.
- `-s read-only` — Codex can read the codebase for context but cannot modify anything.
- `-o` captures output to a file for reliable reading.

### Step 4: Read Review & Check Verdict

1. Read `${TEMP_DIR}/codex-review-${REVIEW_ID}.md`
2. Check the verdict:
   - **Minimum 2 rounds required** — never exit before Round 2, so Codex always re-reviews revisions
   - If round ≥ 2 AND **VERDICT: APPROVED** → go to Step 8 (Done)
   - If **VERDICT: REVISE** → go to Step 5 (Counter-Review)
   - If round ≥ 2 AND no clear verdict but feedback is all positive / no actionable items → treat as approved
   - If max rounds (5) reached → go to Step 8 with a note that max rounds hit

### Step 5: Counter-Review (THIS IS THE KEY DIFFERENCE)

Do NOT blindly revise the plan based on Codex's feedback. Instead, critically evaluate **every** finding Codex raised and assign a disposition:

| Disposition | Meaning | Action |
|-------------|---------|--------|
| **agree** | Codex is right, implement it | Will revise the plan |
| **partial** | Valid point but scope it down | Will revise with reduced scope, note what was scoped out |
| **defer** | Valid but not for this iteration | Log it, don't revise the plan now |
| **reject** | Disagree with Codex's reasoning | Must include rationale for why |

Present the counter-review to the user in this format:

```
## Counter-Review — Round N

| # | Codex Finding | Disposition | Rationale |
|---|--------------|-------------|-----------|
| 1 | [summary] | agree | [why] |
| 2 | [summary] | partial | [what's in scope, what's deferred] |
| 3 | [summary] | reject | [why Codex is wrong here] |
| 4 | [summary] | defer | [valid but out of scope because...] |
```

### Step 6: Decision Gate

If there are any **reject** or **defer** dispositions, present them to the user:

```
### Disputed Findings

Claude rejected the following Codex findings. Please decide for each:

[For each reject:]
1. **[Finding summary]**
   - Codex says: [Codex's argument]
   - Claude says: [Claude's counter-argument]
   - **Your call: side with Codex (revise) or Claude (skip)?**

### Deferred Findings

Claude deferred the following Codex findings. Please confirm or override:

[For each defer:]
2. **[Finding summary]**
   - Codex says: [Codex's argument]
   - Claude says: [why deferring]
   - **OK to defer, or override to revise now?**
```

Wait for the user to respond on each item. For rejects: if the user sides with Codex, move to `agree`. For defers: if the user overrides, move to `agree` (revise now).

If there are no `reject` or `defer` items, skip this step.

### Step 7: Revise & Re-submit

1. **Revise the plan** — apply all `agree` and `partial` findings. Do NOT apply `reject` (user-confirmed) or `defer` items.
2. Rewrite `${TEMP_DIR}/claude-plan-${REVIEW_ID}.md` with the revised plan.
3. Summarize revisions for the user:

```
### Revisions Applied (Round N)
- [What changed and why, one bullet per finding addressed]

### Deferred
- [Findings logged for later]

### Rejected (user-confirmed)
- [Findings skipped with rationale]
```

4. Re-submit to Codex by resuming the existing session:

```bash
codex exec resume "${CODEX_SESSION_ID}" \
  "I've revised the plan based on your feedback. The updated plan is in ${TEMP_DIR}/claude-plan-${REVIEW_ID}.md.

Changes made:
[List specific changes addressing each agreed/partial finding]

Findings I did NOT address (with rationale):
[List any rejected/deferred findings and why]

Please re-review the updated plan. Focus on whether the revisions address your concerns and check for any new issues introduced by the changes.

If the plan is now solid: VERDICT: APPROVED
If more changes needed: VERDICT: REVISE" > "${TEMP_DIR}/codex-round-${ROUND}-${REVIEW_ID}.md" 2>&1
```

Read the FULL output file — do NOT truncate with `tail` or `head`.

**If resume fails** (session expired), fall back to a fresh `codex exec -a never -s read-only` with context about prior rounds in the prompt.

Then go back to **Step 4** (Read Review & Check Verdict).

### Step 8: Write Review Artifact

Write the full review transcript to `docs/reviews/plan-review-{REVIEW_ID}.md` in the current repo. This is the permanent record of the review.

The artifact should contain:

```markdown
# Plan Review: [plan name or topic]

**Review ID:** {REVIEW_ID}
**Date:** [date]
**Model:** [model from codex output]
**Status:** [Approved after N round(s) | Max rounds reached — not fully approved]
**Plan file:** [path to the plan that was reviewed, if applicable]

## Summary

| Metric | Count |
|--------|-------|
| Rounds | N |
| Total findings | X |
| Agreed & applied | X |
| Partially applied | X |
| Deferred | X |
| Rejected | X |

---

## Round 1

### Codex Review

[Full Codex feedback from this round]

### Claude Counter-Review

| # | Codex Finding | Disposition | Rationale |
|---|--------------|-------------|-----------|
| 1 | ... | agree | ... |
| 2 | ... | reject | ... |

### User Decisions

[If any reject disputes were resolved by the user, record them here]
- Finding 2: User sided with [Claude/Codex] — [brief reason if given]

### Revisions Applied

- [Change 1]
- [Change 2]

---

## Round 2
[Same structure as Round 1]

---

## Final Plan

[The complete final plan text after all revisions]

---

## Deferred Items

[Cumulative list of all deferred findings across all rounds — these are the backlog]

## Rejected Items (user-confirmed)

[Cumulative list of all rejected findings with rationale — these were intentionally skipped]
```

**Important:** Include the full Codex feedback and full counter-review tables for every round — not summaries. This is the audit trail.

If `docs/reviews/` does not exist, create it.

### Step 9: Present Final Result

Present a summary to the user in the conversation:

**If approved:**
```
## Plan Review Complete

**Status:** Approved after N round(s)
**Artifact:** docs/reviews/plan-review-{REVIEW_ID}.md

### Review Summary
- Total findings across all rounds: X
- Agreed & applied: X
- Partially applied: X
- Deferred: X
- Rejected: X

[Final Codex approval message]

The plan has been reviewed by Codex and counter-reviewed by Claude. Ready for your approval to implement.
```

**If max rounds reached without approval:**
```
## Plan Review Complete

**Status:** Max rounds (5) reached — not fully approved
**Artifact:** docs/reviews/plan-review-{REVIEW_ID}.md

### Remaining Concerns
[List unresolved findings from last round]

### Deferred Items (from all rounds)
[Cumulative list of deferred findings]

Codex still has concerns. Review the remaining items and decide whether to proceed or continue refining.
```

### Step 10: Cleanup

```bash
python -c "import glob, os, tempfile; [os.remove(f) for f in glob.glob(os.path.join(tempfile.gettempdir(), f'*-${REVIEW_ID}*'))]"
```

## Rules

- Claude **critically evaluates** Codex feedback before revising — this is counter-review, not compliance
- Every Codex finding MUST get a disposition — no silent skipping
- `reject` dispositions MUST go through the user decision gate — Claude cannot unilaterally ignore feedback
- Codex model and reasoning effort are inherited from `~/.codex/config.toml` — do not hardcode `-m` unless the user overrides
- Always use read-only sandbox mode (`-s read-only`) — Codex should never write files
- Minimum 2 rounds (review + re-review), max 5 to prevent infinite loops
- Show the user each round's counter-review and revisions so they can follow along
- If Codex CLI is not installed or fails, inform the user and suggest `npm install -g @openai/codex`
- If a revision contradicts the user's explicit requirements, flag it as `reject` with rationale
- Use Read/Write tools for all file operations — never use `cp`, `mv`, or shell redirects, as these trigger permission prompts
