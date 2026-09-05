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

Requires at least the primary driver. Codex CLI, Claude reviewer channel, and Gemini CLI add council participants when configured. Skill degrades gracefully and works with any subset of models.

---

## Options

Use `effort=<fast|balanced|deep>` as the cross-agent option. Map it to the runtime's native model or reasoning controls where available. Default to `balanced`.

Claude Code compatibility: also accept `model=<sonnet|opus|haiku>` for Claude-native Task dispatch. If present, store it as `CLAUDE_SUB_AGENT_MODEL`; otherwise choose the runtime default for the selected effort. Print the selected effort and any driver-specific model override.

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
- `COUNCIL_REGISTRY`: primary-native participant, external CLI participants, skipped participants, and independence notes

Detect `PRIMARY_DRIVER` from the active runtime:

| Signal | Primary driver |
|--------|----------------|
| Claude Code command context, or tools such as Task/Read/Write/Bash | `claude-code` |
| Codex desktop/app context | `codex-app` |
| Running under `codex exec` / Codex CLI | `codex-cli` |
| Ambiguous runtime | `unknown`; use neutral capabilities and ask only if behavior materially differs |

Participant defaults:

- Claude primary: primary-native Claude plus Codex CLI and Gemini CLI when available. Skip a separate Claude CLI participant by default because it is same-family unless the user explicitly requests it.
- Codex primary: primary-native Codex plus Claude reviewer channel and Gemini CLI when available. A secondary Codex CLI session is allowed only as `secondary same-family review` and is skipped by default unless explicitly requested.
- GitHub review agents are not required for ideation, but if the brief is PR-specific, include relevant GitHub bot feedback as context.

When Codex is the primary driver, external participant subprocesses (`claude`, `gemini`, and optional secondary `codex`) require sandbox and approval settings that permit launching those commands and using their network-backed model sessions. If a subprocess is blocked by policy, mark that participant as skipped and continue.

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
```bash
gemini --version
```

Set `HAS_CODEX`, `HAS_CLAUDE_REVIEWER`, and `HAS_GEMINI` to true/false based on the primary driver and configured reviewer channels. If unavailable, warn but continue:
- Codex missing → "Codex CLI not found. Install: `npm install -g @openai/codex`"
- Claude reviewer missing while Codex is primary → "Claude reviewer channel not found. Continuing without Claude as a council participant."
- Gemini missing → "Gemini CLI not found. Install: `npm install -g @google/gemini-cli`"

Minimum requirement: primary driver alone. Warn the user if fewer than 3 participants are available.

Generate a random 8-character hex string natively (not Bash). Store as `SESSION_ID`.

Set `IDEATION_DIR` to `.review/` in the project root (absolute path). Add `.review/` to `.gitignore` if missing. The directory is created automatically when the primary driver's file-write capability writes the first file into it — do NOT use `mkdir`.

Initialize state file `${IDEATION_DIR}/ideation-state-${SESSION_ID}.json` tracking: `sessionId`, `primaryDriver`, `councilRegistry`, `projectRoot`, `ideationDir`, `externalThreadIds`, `hasCodex`, `hasClaudeReviewer`, `hasGemini`, `deepenRound` (starts at 0), `attachmentPaths`.

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

**Claude reviewer channel under Codex/other primary** (if available):
- Use Claude CLI as the independent Claude participant. Launch it with the shell command working directory set to `PROJECT_ROOT`; do not use `cd`. If the runtime cannot set cwd directly, add `--add-dir "${PROJECT_ROOT}"` and include `PROJECT_ROOT` in the prompt.
  ```bash
  claude -p "Repository root: ${PROJECT_ROOT}. [base prompt]. Read and analyze the following files if accessible: [absolute path for each attachment]. Do not modify files." --permission-mode plan --allowedTools "Read" "Grep" "Glob" --disallowedTools "Edit" "Write" "MultiEdit" --output-format json
  ```
- If `model=<sonnet|opus|haiku>` or an effort mapping selects a Claude model, add the matching Claude `--model` option. If effort is configured and the installed Claude CLI supports it, add `--effort low|medium|high`.
- Parse the Claude JSON natively. Store `session_id` as `externalThreadIds.claude`, extract `result`, and write it to `${IDEATION_DIR}/claude-ideation-${SESSION_ID}.md`.
- Include each attachment path with an explicit instruction: "Use your file-reading capability to view the file at [absolute path]" for reviewers that can access files directly.

**Codex** (if `HAS_CODEX`):
- Codex can read project files via its internal tools. Include the **absolute file paths** in the prompt and instruct: "Read and analyze the file at [path]"
- Codex has limited image interpretation in headless mode — for image attachments, still include the path but note that Codex may not be able to render images visually
- If Codex is primary, skip this participant by default unless the user explicitly requested a secondary Codex perspective; if run, mark it `secondary same-family review`.
```bash
codex exec -s read-only -C "${PROJECT_ROOT}" "[base prompt]. Read and analyze the following files: [absolute path for each attachment]"
```
Capture the output from the shell result and write it to `${IDEATION_DIR}/codex-ideation-${SESSION_ID}.md` using the primary driver's file-write capability.

**Gemini** (if `HAS_GEMINI`):
- Include each attachment using Gemini's `@` file reference syntax inline in the prompt: `@./relative/path/to/file`
- For files copied into `${IDEATION_DIR}/`, use the path relative to the project root (e.g., `@./.review/screenshot.png`)
- Gemini can natively view images, PDFs, and text files via `@` references
```bash
gemini -p "[base prompt]. Analyze the following files: @./relative/path/to/attachment1 @./relative/path/to/attachment2. Do NOT modify any files." -y
```
Capture the output from the shell result and write it to `${IDEATION_DIR}/gemini-ideation-${SESSION_ID}.md` using the primary driver's file-write capability.

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

**Codex** (if `HAS_CODEX`):
```bash
codex exec -s read-only -C "${PROJECT_ROOT}" "[counter-review prompt]"
```
Capture the output from the shell result and write it to `${IDEATION_DIR}/codex-counter-${SESSION_ID}.md` using the primary driver's file-write capability.

**Claude reviewer channel** (if `HAS_CLAUDE_REVIEWER` and Claude was an external participant):
```bash
claude -p "Repository root: ${PROJECT_ROOT}. [counter-review prompt]. Use read-only file access only. Do not modify files." --resume "${CLAUDE_SESSION_ID}" --permission-mode plan --allowedTools "Read" "Grep" "Glob" --disallowedTools "Edit" "Write" "MultiEdit" --output-format json
```
Parse `result` from the JSON and write it to `${IDEATION_DIR}/claude-counter-${SESSION_ID}.md`. If resume fails, run a fresh Claude CLI counter-review with the full synthesis in the prompt and update `externalThreadIds.claude` with the new `session_id`.

**Gemini** (if `HAS_GEMINI`):
```bash
gemini -p "[counter-review prompt]. Do NOT modify any files." -y
```
Capture the output from the shell result and write it to `${IDEATION_DIR}/gemini-counter-${SESSION_ID}.md` using the primary driver's file-write capability.

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
| 1 | [idea] | Claude, Codex, Gemini | [theme] |

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
- Gemini: ${IDEATION_DIR}/gemini-ideation-${SESSION_ID}.md (if Gemini ran)

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

### Step 7: Cleanup

Delete `.review/` and its contents: `rm -rf "${IDEATION_DIR}"` (single Bash command, permission prompt expected).

---

## Rules

- All models get the **same brief** — no model sees another's raw output until the synthesis step
- The primary driver is the **synthesizer**, not a privileged voice — its ideas are attributed and challengeable just like the others
- Codex model inherited from `~/.codex/config.toml` — do not hardcode `-m`
- Gemini model inherited from `~/.gemini/settings.json` (`general.model`) — do not hardcode `-m`
- Always use `-s read-only` for Codex — no file modifications
- Claude CLI participant runs with `--permission-mode plan --output-format json`; capture `session_id` and resume with `--resume` for counter-review when possible
- Launch Claude CLI with command cwd set to `PROJECT_ROOT`; if unavailable, add `--add-dir "${PROJECT_ROOT}"` and include the repo root in the prompt
- Same-family secondary participants are skipped by default unless explicitly requested
- Sandbox or network policy blocks on external participants degrade coverage but do not block ideation
- Use `-y` for Gemini in non-interactive mode — prompt explicitly instructs "do NOT modify any files"
- If a model fails or times out, continue with remaining models (minimum: primary driver alone)
- Use the primary driver's native file-read and file-write capabilities for file operations — never `cp`, `mv`, or shell redirects
- **Never use `cd` in Bash** — use `-C <dir>` for codex/git, absolute paths elsewhere
- **Never use `$()` or pipe to `jq`** — run standalone, parse JSON natively
- Quote all bash variables: `"${VAR}"`
- If Codex CLI missing, suggest `npm install -g @openai/codex`
- If Gemini CLI missing, suggest `npm install -g @google/gemini-cli`
