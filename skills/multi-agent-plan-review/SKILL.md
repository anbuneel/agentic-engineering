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

Send the current implementation plan to one or more external reviewers. The **primary driver** is whichever agent is executing this skill: Claude Code, Codex App, or Codex CLI. The primary driver performs a **counter-review** on each round of external feedback — assigning dispositions (agree/partial/defer/reject) to every finding before revising. Rejected and deferred findings are never silently dropped: they are recorded with both sides' arguments and handed to the user at the end under "Needs your call". The loop never blocks on the user. A round that revises the plan is followed by a verification round; a round with nothing to revise converges. Max 5 rounds.

## When to Invoke

- When the user runs `/multi-agent-plan-review` during or after plan mode
- When the user wants a second opinion on a plan from a different model

## Options

- `effort=<fast|balanced|deep>` — default `balanced`. Maps to reasoning effort only; every driver inherits the user's configured model.
- `model=<fable|opus|sonnet|haiku>` — Claude model override for the Claude reviewer channel.
- `budget=<usd>` — per-run `--max-budget-usd` for the Claude reviewer channel. No cap by default.
- `decisions=<deferred|interactive>` — default `deferred`. Deferred never blocks the loop: reject and defer dispositions are recorded and presented at the end. Interactive asks the user mid-loop.
- `require=<codex|claude>` — make a reviewer required. Default: none required, all advisory.

The mapping table, override rules, and cost notes are in [references/reviewer-contracts.md](references/reviewer-contracts.md). Print the resolved options at startup.

## Runtime Adapter

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

- Claude primary: Codex CLI is the external plan reviewer; use GitHub discussion context if available and useful. Skip a separate Claude CLI reviewer by default because it is same-family unless the user explicitly requests it.
- Codex primary: the Claude reviewer channel is the external plan reviewer when configured. A secondary Codex session is allowed only as `secondary same-family review` and is skipped by default unless explicitly requested.
- GitHub review agents are not required for plan review, but if the plan is tied to a PR, include relevant bot feedback as contextual reviewer input.

Missing external reviewers never block unless the user explicitly requested one. Record skipped reviewers in the final artifact.

When Codex is the primary driver, external reviewer subprocesses (`claude` and optional secondary `codex`) require sandbox and approval settings that permit launching those commands and using their network-backed model sessions. If a subprocess is blocked by policy, mark that reviewer as skipped and continue unless the user explicitly required it.

Reviewer requirement rules:

- By default, no external reviewer is required; configured reviewers are advisory.
- A reviewer becomes required only when the user explicitly requests it.
- Advisory reviewer skips do not block convergence, but must be recorded with confidence notes.
- Required reviewer skips require an explicit user decision to continue degraded, retry, or stop.

## External Reviewer Command Contracts

The invocation, resume, output parsing, read-only flags, and failure handling for the Claude and Codex reviewer channels are in [references/reviewer-contracts.md](references/reviewer-contracts.md). Every reviewer returns the object defined in [references/findings-schema.md](references/findings-schema.md) with the severity enum `MUST_FIX`, `SHOULD_FIX`, `CONSIDER`; `file` is the plan file and `line` is the line in it, or `0` for a plan-wide finding. Write that schema to `${REVIEW_DIR}/findings.schema.json` in Step 1.

Prompts for this skill, substituted into `[PROMPT]` in the contracts:

**Round 1:**

```text
Repository root: ${PROJECT_ROOT}. Review this implementation plan thoroughly: ${REVIEW_DIR}/primary-plan-${REVIEW_ID}.md. Read the codebase as needed to judge feasibility, missing steps, risks, sequencing, and conflicts with existing code. Report each finding with severity MUST_FIX, SHOULD_FIX, or CONSIDER, the plan file path, and the line number (0 for plan-wide issues). Use read-only file access only. Do not modify files. Return only the findings object.
```

**Round 2 and later (resumed session):**

```text
Repository root: ${PROJECT_ROOT}. The plan has been updated. [CHANGE_SUMMARY]. Findings not addressed, with rationale: [REJECTED_AND_DEFERRED]. Updated plan: ${REVIEW_DIR}/primary-plan-${REVIEW_ID}.md. Report whether each previous finding is resolved, and any new findings, using the same severity scale. Do not modify files. Return only the findings object.
```

Output files: `${REVIEW_DIR}/claude-review-round-${ROUND}-${REVIEW_ID}.json` and `${REVIEW_DIR}/codex-review-round-${ROUND}-${REVIEW_ID}.json`.

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
4. Initialize state file `${REVIEW_DIR}/plan-review-state-${REVIEW_ID}.json` tracking: `reviewId`, `primaryDriver`, `options`, `reviewerRegistry`, `round` (starts at 1), `externalThreadIds`, `planFile`, `findings`, `dispositions`, `needsYourCall`. Write the findings schema to `${REVIEW_DIR}/findings.schema.json`.

   **CRITICAL — Read and update this state file after every major step to guard against context compression. After compaction, the state file is the ONLY reliable source of truth. Always re-read it before acting.**

5. Read the plan file with the primary driver's file-read capability, write it to `${REVIEW_DIR}/primary-plan-${REVIEW_ID}.md` with the primary driver's file-write capability. If no plan exists in context, ask the user.

### Step 2: External Review (Round 1)

Run each available external reviewer from `REVIEWER_REGISTRY` with the round-1 prompt and command from the contracts section. Store `thread_id` or `session_id` in the state file the moment it is known. Launch reviewers in parallel when the runtime supports it.

### Step 3: Read Reviews

**At the start of EVERY round, read the state file and restore all variables** (`REVIEW_ID`, `REVIEW_DIR`, `PROJECT_ROOT`, `externalThreadIds`, `round`). After context compaction these values exist ONLY in the state file.

Read every reviewer's findings object from its output file. Compute fingerprints and deduplicate across reviewers as described in [references/findings-schema.md](references/findings-schema.md). Findings already dispositioned in an earlier round (same fingerprint) are not re-evaluated unless the reviewer marks them unresolved. Go to Step 4 with the new findings; if there are none, go straight to Step 5.

### Step 4: Counter-Review

Critically evaluate **every** external reviewer finding and assign a disposition:

| Disposition | Meaning | Action |
|-------------|---------|--------|
| **agree** | Reviewer is right | Revise the plan |
| **partial** | Valid but scope down | Revise with reduced scope, record the rest as defer |
| **defer** | Valid but not now | Record under Needs your call |
| **reject** | Disagree | Record under Needs your call with rationale |

Present the counter-review table to the user:

```
## Counter-Review — Round N

| # | Reviewer Finding | Disposition | Rationale |
|---|------------------|-------------|-----------|
| 1 | [summary] | agree | [why] |
| 2 | [summary] | reject | [counter-argument] |
```

### Step 5: Decisions and Convergence

**Decisions.** With `decisions=deferred` (default): append every reject and defer item to `needsYourCall` with the finding, the reviewer's argument, and the primary driver's argument, then continue. With `decisions=interactive`: present each reject and defer item with both sides and wait; the user's call becomes the disposition.

**Convergence.** `revisionsThisRound` is true when any new finding has disposition `agree` or `partial`.

- `revisionsThisRound` → not converged; go to Step 6, and a verification round follows.
- A required reviewer (`require=`) whose latest verdict is `REVISE` and was not skipped by user decision → not converged; go to Step 6 even without revisions, resubmitting the current plan with the rejected findings and rationale.
- Otherwise → converged, including a clean round 1. Go to Step 7.
- Round 5 without convergence → go to Step 7 with a warning.

### Step 6: Revise & Re-submit

1. Apply all `agree` and `partial` findings. Leave `reject` and `defer` items as they are.
2. Rewrite `${REVIEW_DIR}/primary-plan-${REVIEW_ID}.md`.
3. Summarize to the user: what changed and what is waiting under Needs your call.
4. Resume each external reviewer session with the round-2 prompt and resume command from the contracts section, using the ids in `externalThreadIds`. On a resume failure, fall back to the round-1 command with the prior-round context in the prompt and store the new id.
5. Increment `round` in the state file. Go back to **Step 3**.

### Step 7: Write Review Artifact

Write the full review transcript to `docs/reviews/plan-review-${REVIEW_ID}.md`. Create `docs/reviews/` if needed.

Include these sections:
- **Metadata** — review ID, date, primary driver, options, reviewer registry, status (converged / max rounds), plan file path
- **Summary metrics** — rounds, findings by disposition (agreed, partial, deferred, rejected)
- **Each round** — full external reviewer feedback, full counter-review table, revisions applied
- **Final plan** — complete text after all revisions
- **Needs your call** — every reject and defer item with the reviewer's argument and the primary driver's argument side by side
- **Confidence notes** — reviewers available, reviewers skipped, and any degraded-coverage implications

**Important:** Full audit trail — complete external reviewer feedback and counter-review tables, not summaries.

### Step 8: Present Final Result

Present status (converged or max rounds), the artifact path, summary metrics, and the Needs your call list. This is the one place the user is asked to decide, and nothing waits on the answer.

### Step 9: Wrap Up

Leave `.review/` in place. It is gitignored and every file carries the review id, so nothing needs deleting.

## Rules

- Primary driver **critically evaluates** external reviewer feedback — counter-review, not compliance
- Every finding gets a disposition; reject and defer are recorded with both sides and surfaced under Needs your call, never dropped
- The loop never waits on the user unless `decisions=interactive`
- Every driver inherits the user's configured model; `effort=` maps to reasoning effort only, `model=` overrides Claude only
- External reviewer commands, flags, output parsing, and resume rules come from `references/reviewer-contracts.md`; every reviewer returns the `references/findings-schema.md` object
- Required external reviewers default to none; only user-explicit reviewers are required
- Sandbox or network policy blocks on advisory reviewers degrade coverage but do not block convergence
- A round that revises the plan is followed by a verification round; a round with nothing to revise converges, including a clean round 1. Max 5 rounds
- If Codex CLI is missing or older than the configured model, record the Codex channel as skipped with the reason and suggest `npm install -g @openai/codex`
- If Claude reviewer channel is missing while Codex is primary, record it as skipped and continue unless explicitly required
- If a revision contradicts user's explicit requirements, flag as `reject`
- Use the primary driver's native file-read and file-write capabilities for file operations — never `cp`, `mv`, or shell redirects
- **Never use `cd` in Bash** — use `-C <dir>` for codex/git, `--repo` for gh
- **Never use `$()` or pipe to `jq`** — run standalone, parse JSON natively
