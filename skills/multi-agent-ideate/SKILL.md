---
name: multi-agent-ideate
description: >
  Gather independent perspectives from available model reviewers on any
  topic — architecture, naming, API design, UI, tradeoffs. Available
  participants brainstorm in parallel, then the primary driver synthesizes. Use when the user
  wants multi-model brainstorming, a "second opinion" from multiple
  models, says "let's brainstorm", "get ideas from different models",
  "what do other models think", or wants diverse AI perspectives on a
  decision.
---

# Multi-Agent Ideate (Agent-Agnostic Multi-Model Council)

Gather independent perspectives from available model reviewers on any topic — UI design, architecture, naming, API design, tradeoffs, or any question where diverse viewpoints add value. The **primary driver** is whichever agent is executing this skill: Claude Code, Codex App, or Codex CLI. Available participants brainstorm in parallel, then the primary driver synthesizes and each available participant counter-reviews the synthesis.

## When to Invoke

- When the user runs `/multi-agent-ideate`
- When the user wants multi-model brainstorming or a "second opinion" from multiple models

## Prerequisites

Requires at least the primary driver. Codex CLI (under Claude primary) or the Claude reviewer channel (under Codex primary) adds the cross-family council participant when configured. Skill degrades gracefully and works with any subset of models.

---

## Options

- `effort=<fast|balanced|deep>` — default `balanced`. Maps to reasoning effort only; every driver inherits the user's configured model.
- `model=<fable|opus|sonnet|haiku>` — Claude model override for native subagents and the Claude participant.
- `budget=<usd>` — per-run `--max-budget-usd` for the Claude participant. No cap by default.

The mapping table, override rules, and cost notes are in [references/reviewer-contracts.md](references/reviewer-contracts.md). Print the resolved effort, model override, and budget at startup.

External participants use the commands in that file without a findings schema: ideation and counter-review are free text, so Codex gets `-o` with a `.md` path and no `--output-schema`, and Claude's answer is read from `result`.

---

## Runtime Adapter

At startup, identify and store:

- `PRIMARY_DRIVER`: `claude-code`, `codex-app`, `codex-cli`, or `unknown`
- `COUNCIL_REGISTRY`: primary-native participant, external CLI participants, skipped participants, and independence notes

Detect `PRIMARY_DRIVER` from the active runtime:

| Signal | Primary driver |
|--------|----------------|
| Claude Code command context, or tools such as Task/Read/Write/Bash | `claude-code` |
| Codex desktop/app context | `codex-app` |
| Running under `codex exec` / Codex CLI | `codex-cli` |
| Ambiguous runtime | `unknown`; use neutral capabilities and ask only if behavior materially differs |

Participant defaults:

- Claude primary: primary-native Claude plus Codex CLI when available. Skip a separate Claude CLI participant by default because it is same-family unless the user explicitly requests it.
- Codex primary: primary-native Codex plus the Claude reviewer channel when available. A secondary Codex CLI session is allowed only as `secondary same-family review` and is skipped by default unless explicitly requested.
- GitHub review agents are not required for ideation, but if the brief is PR-specific, include relevant GitHub bot feedback as context.

When Codex is the primary driver, external participant subprocesses (`claude` and optional secondary `codex`) require sandbox and approval settings that permit launching those commands and using their network-backed model sessions. If a subprocess is blocked by policy, mark that participant as skipped and continue.

---

## Agent Instructions

When invoked, execute the following steps sequentially.

---

### Step 0: Preflight

Run ALL checks:

```bash
git rev-parse --show-toplevel
```

Store as `PROJECT_ROOT`. **Bash safety rules for the entire skill:**
- **Never use `cd`** — use `-C "${PROJECT_ROOT}"` for codex/git, absolute paths elsewhere
- **Never use `$()`** command substitution — run commands standalone, parse output natively
- **Never pipe to `jq`** — parse JSON natively in-context

```bash
codex --version
```
```bash
claude --version
```

Set `HAS_CODEX` and `HAS_CLAUDE_REVIEWER` to true/false based on the primary driver and configured reviewer channels. If unavailable, warn but continue:
- Codex missing → "Codex CLI not found. Install: `npm install -g @openai/codex`"
- Claude reviewer missing while Codex is primary → "Claude reviewer channel not found. Continuing without Claude as a council participant."

Minimum requirement: primary driver alone. Warn the user if no cross-family participant is available, since the council then has a single model family.

Generate a random 8-character hex string natively (not Bash). Store as `SESSION_ID`.

Set `IDEATION_DIR` to `.review/` in the project root (absolute path). Add `.review/` to `.gitignore` if missing. The directory is created automatically when the primary driver's file-write capability writes the first file into it — do NOT use `mkdir`.

Initialize state file `${IDEATION_DIR}/ideation-state-${SESSION_ID}.json` tracking: `sessionId`, `primaryDriver`, `councilRegistry`, `projectRoot`, `ideationDir`, `externalThreadIds`, `hasCodex`, `hasClaudeReviewer`, `deepenRound` (starts at 0), `attachmentPaths`.

**CRITICAL — Read and update this state file after every major step to guard against context compression. After compaction, the state file is the ONLY reliable source of truth. Always re-read it before acting.**

---

### Step 1: Capture Brief

If the user provided a topic/question with the `/multi-agent-ideate` command, use it. Otherwise, ask:

> What would you like the model council to brainstorm on?
>
> 1. **Topic / question** (required)
> 2. **Attachments** — file paths, screenshots, code snippets (optional)
> 3. **Focus areas** — specific aspects to concentrate on (optional)
> 4. **Constraints** — anything to rule out (optional)

Store the full brief. If attachments are provided (screenshots, files, code):
- Files within the project → store their **absolute paths** in a list called `ATTACHMENT_PATHS`
- Files outside the project → copy into `${IDEATION_DIR}/` using the primary driver's file-read and file-write capabilities, then add the new path to `ATTACHMENT_PATHS`
- **CRITICAL: Never summarize or describe attachments as text substitutes. Always pass the actual file paths to each model so they can read/view the files themselves.**

Write the brief to `${IDEATION_DIR}/brief-${SESSION_ID}.md`.

---

### Step 2: Parallel Ideation

Build a prompt for each model. The core content is the same; only the input format differs.

**Base prompt (adapt per model):**

```
You are one voice in a multi-model brainstorming council. Your job is to provide
independent, creative, and practical ideas. Do NOT modify any files.

TOPIC:
[user's topic/question]

CONTEXT:
[attachments / referenced files / screenshots — as applicable]

FOCUS AREAS:
[user's focus areas, or "None specified — cover whatever you think matters"]

CONSTRAINTS:
[user's constraints, or "None"]

Provide your ideas, suggestions, and analysis. Be specific and actionable.
Think creatively — don't hold back. Structure your response however feels
natural, but make each distinct idea clearly identifiable.
```

Run all available participants **in parallel**:

**Primary driver** — Produce a native ideation response with the base prompt. Save it to `${IDEATION_DIR}/primary-ideation-${SESSION_ID}.md`.

**Claude voice under Claude primary**:
- The primary driver already contributes the main Claude perspective.
- Optionally add a specialized native Claude subagent as an additional lens, not as an independent external reviewer. For UI/UX topics, use `frontend-design` if available; otherwise use a general native subagent or run the same prompt as a primary-native design lens and record the fallback.
- For non-UI topics, use a general-purpose native subagent only when it adds a distinct lens; otherwise skip a redundant second Claude voice.

**Claude participant under Codex primary** (if `HAS_CLAUDE_REVIEWER`):
- Run the Claude round-1 command from [references/reviewer-contracts.md](references/reviewer-contracts.md) with this prompt: "Repository root: ${PROJECT_ROOT}. [base prompt]. Use your file-reading capability to read and analyze each of these files: [absolute path for each attachment]. Do not modify files."
- Store `session_id` as `externalThreadIds.claude`, extract `result`, and write it to `${IDEATION_DIR}/claude-ideation-${SESSION_ID}.md`.

**Codex participant under Claude primary** (if `HAS_CODEX`):
- Run the Codex round-1 command from the contracts with `-o "${IDEATION_DIR}/codex-ideation-${SESSION_ID}.md"` and no `--output-schema`, with this prompt: "[base prompt]. Read and analyze the following files: [absolute path for each attachment]. Do not modify files."
- Store `thread_id` as `externalThreadIds.codex`. Codex reads project files with its own tools; for image attachments include the path but note that headless Codex may not render images.
- If Codex is primary, skip this participant by default unless the user explicitly requested a secondary Codex perspective; if run, mark it `secondary same-family review`.

Wait for all to complete. Read all output files.

If any model fails or times out, log the error and continue with remaining models.

---

### Step 3: Synthesize

The primary driver reads all raw responses and produces a unified synthesis:

1. **Identify distinct ideas** across all responses
2. **Group by theme** — let categories emerge naturally from the content (e.g., layout, performance, naming, architecture, UX, security...)
3. **Tag consensus level** for each idea:
   - **Consensus** — 2+ models independently suggested the same or very similar thing
   - **Unique** — only one model suggested it (note which one)
   - **Contested** — models offered conflicting perspectives on the same aspect
4. **Preserve attribution** — note which model(s) contributed each idea
5. **Do NOT filter or rank yet** — include everything

Write synthesis to `${IDEATION_DIR}/synthesis-${SESSION_ID}.md`.

Present the synthesis to the user as a progress update before proceeding.

---

### Step 4: Counter-Review

Send the synthesis back to each available external participant for reactions. Each participant sees ALL ideas (including their own) and the consensus tags.

**Counter-review prompt (adapt per model):**

```
Here is a synthesized list of ideas from a multi-model brainstorming session.
You were one of the participants. Review the synthesis and for EACH idea, respond with one of:

- ENDORSE — you agree this is a good idea
- CHALLENGE — you disagree or see problems (explain why)
- ENHANCE — you'd build on it or add nuance (explain how)
- NEW — something important that was missed in the synthesis

Be specific and critical. Don't just say "endorse all." Do NOT modify any files.

[full synthesis content]
```

Run in parallel:

Before launching external counter-reviewers, read the state file and restore `externalThreadIds`, including `externalThreadIds.claude` when Claude CLI participated.

**Codex** (if Codex participated): resume `externalThreadIds.codex` with the Codex resume command from the contracts, `-o "${IDEATION_DIR}/codex-counter-${SESSION_ID}.md"`, no `--output-schema`, and the counter-review prompt.

**Claude** (if Claude participated): resume `externalThreadIds.claude` with the Claude resume command from the contracts and the prompt "Repository root: ${PROJECT_ROOT}. [counter-review prompt]. Use read-only file access only. Do not modify files." Write `result` to `${IDEATION_DIR}/claude-counter-${SESSION_ID}.md`.

If either resume fails, run the round-1 command with the full synthesis in the prompt and store the new id.

The primary driver also performs its own counter-review natively — evaluating the synthesis critically, especially ideas from external participants that may have been over- or under-weighted during synthesis.

Read all counter-review outputs.

---

### Step 5: Final Report

The primary driver produces the final report incorporating all counter-review feedback.

**Report structure:**

```markdown
# Ideation Report — [Topic Summary]

**Session:** [SESSION_ID]
**Date:** [date]
**Primary Driver:** [driver]
**Participants:** [list of models that participated]
**Skipped Participants:** [list and reason]

## Overview
[1-3 sentence summary of key themes and overall direction]

## Consensus Ideas
Ideas with broad agreement across models — highest confidence.

| # | Idea | Endorsed By | Category |
|---|------|-------------|----------|
| 1 | [idea] | Claude, Codex | [theme] |

[For each: brief description and any enhancements from counter-review]

## Strong Unique Ideas
Suggested by one model, endorsed or enhanced by others in counter-review.

[For each: the idea, who proposed it, who endorsed it, any enhancements]

## Contested Ideas
Models disagree — both sides presented for user decision.

[For each: the idea, who supports it, who challenges it, the arguments on each side]

## Additional Ideas
Unique suggestions not yet validated by other models. Worth considering.

[For each: the idea, which model proposed it, brief rationale]

## New Ideas from Counter-Review
Ideas that emerged during the counter-review round.

[For each: the idea, which model added it]

## Raw Responses
[List only files that were actually written.]

- Primary driver: ${IDEATION_DIR}/primary-ideation-${SESSION_ID}.md
- Claude: ${IDEATION_DIR}/claude-ideation-${SESSION_ID}.md (if Claude ran)
- Codex: ${IDEATION_DIR}/codex-ideation-${SESSION_ID}.md (if Codex ran)

## Skipped Participants
[Participant, reason, and confidence impact.]
```

Write to `${IDEATION_DIR}/report-${SESSION_ID}.md`.

---

### Step 6: Present & Next Steps

Present the final report to the user. Offer options:

> Which ideas would you like to pursue?
>
> 1. **Pick ideas** — select specific ideas by number to act on
> 2. **Go deeper** — explore any contested or unique idea further with a focused round
> 3. **Refine & re-run** — narrow the brief and run another council session
> 4. **Export & close** — save the report and clean up

If the user picks "Go deeper," loop back to Step 2 with a narrowed prompt focused on the selected ideas. Use the same `SESSION_ID` but append `-r2`, `-r3`, etc. to filenames.

---

### Step 7: Wrap Up

Leave `.review/` in place. It is gitignored and every file carries the session id, so nothing needs deleting. Tell the user where the report and raw responses are.

---

## Rules

- All models get the **same brief** — no model sees another's raw output until the synthesis step
- The primary driver is the **synthesizer**, not a privileged voice — its ideas are attributed and challengeable just like the others
- Every driver inherits the user's configured model; `effort=` maps to reasoning effort only, `model=` overrides Claude only
- External participant commands, flags, output parsing, and resume rules come from `references/reviewer-contracts.md`
- Same-family secondary participants are skipped by default unless explicitly requested
- Sandbox or network policy blocks on external participants degrade coverage but do not block ideation
- If a model fails or times out, continue with remaining models (minimum: primary driver alone)
- Use the primary driver's native file-read and file-write capabilities for file operations — never `cp`, `mv`, or shell redirects
- **Never use `cd` in Bash** — use `-C <dir>` for codex/git, absolute paths elsewhere
- **Never use `$()` or pipe to `jq`** — run standalone, parse JSON natively
- Quote all bash variables: `"${VAR}"`
- If Codex CLI is missing or older than the configured model, record the Codex participant as skipped with the reason and suggest `npm install -g @openai/codex`
