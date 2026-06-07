---
name: multi-agent-plan-review
description: >
  Send an implementation plan to an external reviewer for multi-agent
  review, with the primary driver counter-reviewing each finding. Use when the user
  wants a second opinion on a plan, asks to review a plan with another
  model, or says "have Codex review this plan", "have Claude review this plan",
  "get feedback on my
  plan", or "multi-agent plan review". Best used during or after plan mode.
---

# Multi-Agent Plan Review (Agent-Agnostic with Counter-Review)

Send the current implementation plan to one or more external reviewers. The **primary driver** is whichever agent is executing this skill: Claude Code, Codex App, or Codex CLI. The primary driver performs a **counter-review** on each round of external feedback — assigning dispositions (agree/partial/defer/reject) to every finding before revising. When the primary driver rejects or defers a finding, the **user breaks the tie**. Min 2 rounds, max 5.

## When to Invoke

- When the user runs `/multi-agent-plan-review` during or after plan mode
- When the user wants a second opinion on a plan from a different model

## Runtime Adapter

Use `effort=<fast|balanced|deep>` as the cross-agent option. Map it to the current runtime's native model or reasoning controls where available. Claude Code compatibility: also accept `model=<sonnet|opus|haiku>` for Claude-native subagent/reviewer calls.

Effort mapping:

| Effort | Claude-native / Claude CLI | Codex CLI | Reviewer timeouts |
|--------|-----------------------------|-----------|-------------------|
| `fast` | Prefer Haiku when selecting a Claude model; pass `--effort low` when supported | Prefer inherited `~/.codex/config.toml`; if overriding effort, use `-c model_reasoning_effort="low"` | Shortest |
| `balanced` | Prefer Sonnet when selecting a Claude model; pass `--effort medium` when supported | Prefer inherited config; if overriding effort, use `-c model_reasoning_effort="medium"` | Default |
| `deep` | Prefer Opus when selecting a Claude model and the user accepts cost; pass `--effort high` when supported | Prefer inherited config; if overriding effort, use `-c model_reasoning_effort="high"` | Longest |

`model=<sonnet|opus|haiku>` overrides only Claude model selection. Do not hardcode a Codex model with `-m`; Codex model selection is inherited unless the user explicitly requests otherwise.

At startup, identify and store:

- `PRIMARY_DRIVER`: `claude-code`, `codex-app`, `codex-cli`, or `unknown`
- `REVIEWER_REGISTRY`: available external reviewers, skipped reviewers, and independence notes

Detect `PRIMARY_DRIVER` from the active runtime:

| Signal | Primary driver |
|--------|----------------|
| Claude Code command context, or tools such as Task/Read/Write/Bash | `claude-code` |
| Codex desktop/app context | `codex-app` |
| Running under `codex exec` / Codex CLI | `codex-cli` |
| Ambiguous runtime | `unknown`; use neutral capabilities and ask only if behavior materially differs |

Reviewer defaults:

- Claude primary: prefer Codex CLI as the external plan reviewer; use Gemini CLI or GitHub discussion context if available and useful. Skip a separate Claude CLI reviewer by default because it is same-family unless the user explicitly requests it.
- Codex primary: prefer a Claude reviewer channel when configured; use Gemini CLI as an additional reviewer. A secondary Codex session is allowed only as `secondary same-family review` and is skipped by default unless explicitly requested.
- GitHub review agents are not required for plan review, but if the plan is tied to a PR, include relevant bot feedback as contextual reviewer input.

Missing external reviewers never block unless the user explicitly requested one. Record skipped reviewers in the final artifact.

When Codex is the primary driver, external reviewer subprocesses (`claude`, `gemini`, and optional secondary `codex`) require sandbox and approval settings that permit launching those commands and using their network-backed model sessions. If a subprocess is blocked by policy, mark that reviewer as skipped and continue unless the user explicitly required it.

Reviewer requirement rules:

- By default, no external reviewer is required; configured reviewers are advisory.
- A reviewer becomes required only when the user explicitly requests it.
- Advisory reviewer skips do not block convergence, but must be recorded with confidence notes.
- Required reviewer skips require an explicit user decision to continue degraded, retry, or stop.

## External Reviewer Command Contracts

Every external CLI reviewer must be read-only and must end with exactly one verdict line:

```text
VERDICT: APPROVED
```

or

```text
VERDICT: REVISE
```

Claude CLI must be launched with the shell command working directory set to `PROJECT_ROOT`; do not use `cd` to get there. The Claude process has no `-C` equivalent, so if the primary runtime cannot set command cwd directly, add `--add-dir "${PROJECT_ROOT}"` and include `PROJECT_ROOT` in the prompt.

**Claude CLI, Round 1** (`externalThreadIds.claude` is null in state):

```bash
claude -p "Repository root: ${PROJECT_ROOT}. Review this plan thoroughly: ${REVIEW_DIR}/primary-plan-${REVIEW_ID}.md. Use read-only file access only. Do not modify files. End with exactly: VERDICT: APPROVED or VERDICT: REVISE" --permission-mode plan --allowedTools "Read" "Grep" "Glob" --disallowedTools "Edit" "Write" "MultiEdit" --output-format json
```

If `model=<sonnet|opus|haiku>` or an effort mapping selects a Claude model, add the matching Claude `--model` option. If effort is configured and the installed Claude CLI supports it, add `--effort low|medium|high`.

Parse the JSON response natively. Store `session_id` as `externalThreadIds.claude` immediately. Extract review text from `result` and write it to `${REVIEW_DIR}/claude-review-round-1-${REVIEW_ID}.md`.

**Claude CLI, Round 2+** (`externalThreadIds.claude` exists in state):

```bash
claude -p "Repository root: ${PROJECT_ROOT}. Plan has been updated. [CHANGE_SUMMARY]. Updated plan: ${REVIEW_DIR}/primary-plan-${REVIEW_ID}.md. Re-review prior findings and any new issues using read-only file access only. Do not modify files. End with exactly: VERDICT: APPROVED or VERDICT: REVISE" --resume "${CLAUDE_SESSION_ID}" --permission-mode plan --allowedTools "Read" "Grep" "Glob" --disallowedTools "Edit" "Write" "MultiEdit" --output-format json
```

If resume fails, fall back to a fresh Claude CLI review with prior-round context in the prompt, capture the new `session_id`, and update `externalThreadIds.claude`.

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
3. Set `REVIEW_DIR` to `.review/` in the project root (absolute path). Add `.review/` to `.gitignore` if missing. The directory is created automatically when the primary driver's file-write capability writes the first file into it — do NOT use `mkdir`.
4. Initialize state file `${REVIEW_DIR}/plan-review-state-${REVIEW_ID}.json` tracking: `reviewId`, `primaryDriver`, `reviewerRegistry`, `round` (starts at 1), `externalThreadIds`, `planFile`, `findings`, `dispositions`.

   **CRITICAL — Read and update this state file after every major step to guard against context compression. After compaction, the state file is the ONLY reliable source of truth. Always re-read it before acting.**

5. Read the plan file with the primary driver's file-read capability, write it to `${REVIEW_DIR}/primary-plan-${REVIEW_ID}.md` with the primary driver's file-write capability. If no plan exists in context, ask the user.

### Step 2: External Review (Round 1)

Run each available external reviewer from `REVIEWER_REGISTRY` with the same read-only prompt. For Codex CLI:

```bash
codex exec --json \
  -s read-only \
  -C "${PROJECT_ROOT}" \
  "Review this plan thoroughly: ${REVIEW_DIR}/primary-plan-${REVIEW_ID}.md

End with exactly: VERDICT: APPROVED or VERDICT: REVISE"
```

The `--json` flag outputs structured JSONL. The first line is always `{"type":"thread.started","thread_id":"<UUID>"}`. Parse `thread_id` and save as `externalThreadIds.codex` in the state file immediately — this survives context compaction. Extract review content from `item.completed` events (the `text` field) and write to `${REVIEW_DIR}/codex-review-${REVIEW_ID}.md`.

For Claude reviewer channels, use the concrete Claude CLI contract above. Capture `session_id` as `externalThreadIds.claude`, extract `result`, and write the raw review to `${REVIEW_DIR}/claude-review-round-1-${REVIEW_ID}.md`.

For Gemini reviewer channels, use a read-only prompt and write the raw response to `${REVIEW_DIR}/gemini-review-round-1-${REVIEW_ID}.md`:

```bash
gemini -p "Review this plan thoroughly: ${REVIEW_DIR}/primary-plan-${REVIEW_ID}.md. Do NOT modify files. End with exactly: VERDICT: APPROVED or VERDICT: REVISE" -y
```

Capture Gemini output from the shell result and write it with the primary driver's file-write capability. Do not use shell redirects.

### Step 3: Read Review & Check Verdict

**At the start of EVERY round, read the state file and restore all variables** (`REVIEW_ID`, `REVIEW_DIR`, `PROJECT_ROOT`, `externalThreadIds`, `round`). After context compaction these values exist ONLY in the state file.

1. Extract review content from every external reviewer output. Write each raw review to `${REVIEW_DIR}/{reviewer}-review-round-${ROUND}-${REVIEW_ID}.md`.
2. Check verdict:
   - **Minimum 2 rounds required** - never exit before Round 2
   - Round >= 2 AND all explicitly required reviewers with verdicts report **VERDICT: APPROVED**, or were skipped by user decision, and advisory reviewer findings are counter-reviewed -> go to Step 7 (Done)
   - Any required reviewer returns **VERDICT: REVISE**, or any advisory reviewer returns new un-dispositioned findings -> go to Step 4 (Counter-Review)
   - Round >= 2 AND no actionable items -> treat as approved, even if advisory reviewers were skipped
   - Max rounds (5) -> go to Step 7 with warning

### Step 4: Counter-Review

Critically evaluate **every** external reviewer finding and assign a disposition:

| Disposition | Meaning | Action |
|-------------|---------|--------|
| **agree** | Reviewer is right | Revise the plan |
| **partial** | Valid but scope down | Revise with reduced scope |
| **defer** | Valid but not now | Log for later |
| **reject** | Disagree | Must include rationale |

Present the counter-review table to the user:

```
## Counter-Review — Round N

| # | Reviewer Finding | Disposition | Rationale |
|---|------------------|-------------|-----------|
| 1 | [summary] | agree | [why] |
| 2 | [summary] | reject | [counter-argument] |
```

### Step 5: Decision Gate

If there are **reject** or **defer** dispositions, present each to the user with both sides' arguments. Wait for their call on each item. If user sides with the reviewer → move to `agree`. If user confirms defer → keep as `defer`.

If no reject/defer items, skip this step.

### Step 6: Revise & Re-submit

1. Apply all `agree` and `partial` findings. Skip `reject` (user-confirmed) and `defer`.
2. Rewrite `${REVIEW_DIR}/primary-plan-${REVIEW_ID}.md`.
3. Summarize to the user: what changed, what's deferred, what's rejected.
4. Resume each external reviewer session that supports resume. For Codex CLI, use `externalThreadIds.codex` from the state file:

```bash
codex exec resume "${CODEX_THREAD_ID}" --json "I've revised the plan. Updated plan: ${REVIEW_DIR}/primary-plan-${REVIEW_ID}.md. [Changes made. Findings not addressed with rationale.] Re-review. End with exactly: VERDICT: APPROVED or VERDICT: REVISE"
```

Extract review content from `item.completed` events as in Round 1.

**If resume fails**, fall back to fresh `codex exec --json -s read-only -C "${PROJECT_ROOT}"` with prior round context. Capture the new `thread_id` and update state.

For Claude CLI, use `externalThreadIds.claude` from the state file:

```bash
claude -p "Repository root: ${PROJECT_ROOT}. Plan has been updated. [CHANGE_SUMMARY]. Updated plan: ${REVIEW_DIR}/primary-plan-${REVIEW_ID}.md. Re-review prior findings and any new issues using read-only file access only. Do not modify files. End with exactly: VERDICT: APPROVED or VERDICT: REVISE" --resume "${CLAUDE_SESSION_ID}" --permission-mode plan --allowedTools "Read" "Grep" "Glob" --disallowedTools "Edit" "Write" "MultiEdit" --output-format json
```

Extract review content from `result` as in Round 1. If resume fails, fall back to a fresh Claude CLI review with prior round context, capture the new `session_id`, and update state.

5. Increment `round` in the state file. Go back to **Step 3**.

### Step 7: Write Review Artifact

Write the full review transcript to `docs/reviews/plan-review-${REVIEW_ID}.md`. Create `docs/reviews/` if needed.

Include these sections:
- **Metadata** — review ID, date, primary driver, reviewer registry, status (approved / max rounds), plan file path
- **Summary metrics** — rounds, findings by disposition (agreed, partial, deferred, rejected)
- **Each round** — full external reviewer feedback, full counter-review table, user decisions on disputes, revisions applied
- **Final plan** — complete text after all revisions
- **Deferred items** — cumulative across all rounds
- **Rejected items** — user-confirmed, with rationale
- **Confidence notes** — reviewers available, reviewers skipped, and any degraded-coverage implications

**Important:** Full audit trail — complete external reviewer feedback and counter-review tables, not summaries.

### Step 8: Present Final Result

Present status (approved or max rounds), link to artifact, summary metrics, and any remaining concerns or deferred items.

### Step 9: Cleanup

Delete `.review/` and its contents: `rm -rf "${REVIEW_DIR}"` (single Bash command, permission prompt expected).

## Rules

- Primary driver **critically evaluates** external reviewer feedback — counter-review, not compliance
- Every finding MUST get a disposition — no silent skipping
- `reject` dispositions MUST go through the user decision gate
- Codex model inherited from `~/.codex/config.toml` — do not hardcode `-m`
- Always use `-s read-only` — Codex should never write files
- Claude CLI reviewer runs with `--permission-mode plan --output-format json`; capture `session_id` and resume with `--resume`
- Launch Claude CLI with command cwd set to `PROJECT_ROOT`; if unavailable, add `--add-dir "${PROJECT_ROOT}"` and include the repo root in the prompt
- Required external reviewers default to none; only user-explicit reviewers are required
- Sandbox or network policy blocks on advisory reviewers degrade coverage but do not block convergence
- Minimum 2 rounds, max 5
- If Codex CLI missing, suggest `npm install -g @openai/codex`
- If Claude reviewer channel is missing while Codex is primary, record it as skipped and continue unless explicitly required
- If a revision contradicts user's explicit requirements, flag as `reject`
- Use the primary driver's native file-read and file-write capabilities for file operations — never `cp`, `mv`, or shell redirects
- **Never use `cd` in Bash** — use `-C <dir>` for codex/git, `--repo` for gh
- **Never use `$()` or pipe to `jq`** — run standalone, parse JSON natively
