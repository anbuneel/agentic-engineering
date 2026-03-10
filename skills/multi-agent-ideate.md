---
name: multi-agent-ideate
description: >
  Gather independent perspectives from Claude, Codex, and Gemini on any
  topic — architecture, naming, API design, UI, tradeoffs. All three
  brainstorm in parallel, then Claude synthesizes. Use when the user
  wants multi-model brainstorming, a "second opinion" from multiple
  models, says "let's brainstorm", "get ideas from different models",
  "what do other models think", or wants diverse AI perspectives on a
  decision.
---

# Multi-Agent Ideate (Multi-Model Council)

Gather independent perspectives from Claude, Codex, and Gemini on any topic — UI design, architecture, naming, API design, tradeoffs, or any question where diverse viewpoints add value. All three models brainstorm in parallel, then Claude synthesizes and each model counter-reviews the synthesis.

## When to Invoke

- When the user runs `/multi-agent-ideate`
- When the user wants multi-model brainstorming or a "second opinion" from multiple models

## Prerequisites

Requires **codex CLI** and **gemini CLI** for full council. Claude runs natively. Skill degrades gracefully — works with any subset of models.

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
gemini --version
```

Set `HAS_CODEX` and `HAS_GEMINI` to true/false. If unavailable, warn but continue:
- Codex missing → "Codex CLI not found. Install: `npm install -g @openai/codex`"
- Gemini missing → "Gemini CLI not found. Install: `npm install -g @google/gemini-cli`"

Minimum requirement: Claude alone. Warn the user if fewer than 3 models are available.

Generate a random 8-character hex string natively (not Bash). Store as `SESSION_ID`.

Set `IDEATION_DIR` to `.review/` in the project root (absolute path). Add `.review/` to `.gitignore` if missing. The directory is created automatically when the Write tool writes the first file into it — do NOT use `mkdir`.

Initialize state file `${IDEATION_DIR}/ideation-state-${SESSION_ID}.json` tracking: `sessionId`, `projectRoot`, `ideationDir`, `hasCodex`, `hasGemini`, `deepenRound` (starts at 0), `attachmentPaths`.

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
- Files outside the project → copy into `${IDEATION_DIR}/` using Read then Write tools, then add the new path to `ATTACHMENT_PATHS`
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

Run all available models **in parallel**:

**Claude** — Launch a Task agent:
- If the topic is **UI/UX related** (design feedback, layout, styling, components, visual improvements), use `subagent_type: frontend-design` — this leverages the specialized frontend-design skill for higher-quality UI/UX output
- For **all other topics** (architecture, naming, API design, performance, etc.), use `subagent_type: general-purpose`
- Prompt with the base template
- **Include each attachment path with an explicit instruction:** "Use the Read tool to view the file at [absolute path]" — for images this gives Claude native multimodal viewing
- Save the agent's response to `${IDEATION_DIR}/claude-ideation-${SESSION_ID}.md` using the Write tool

**Codex** (if `HAS_CODEX`):
- Codex can read project files via its internal tools. Include the **absolute file paths** in the prompt and instruct: "Read and analyze the file at [path]"
- Codex has limited image interpretation in headless mode — for image attachments, still include the path but note that Codex may not be able to render images visually
```bash
codex exec -s read-only -C "${PROJECT_ROOT}" -o "${IDEATION_DIR}/codex-ideation-${SESSION_ID}.md" "[base prompt]. Read and analyze the following files: [absolute path for each attachment]"
```

**Gemini** (if `HAS_GEMINI`):
- Include each attachment using Gemini's `@` file reference syntax inline in the prompt: `@./relative/path/to/file`
- For files copied into `${IDEATION_DIR}/`, use the path relative to the project root (e.g., `@./.review/screenshot.png`)
- Gemini can natively view images, PDFs, and text files via `@` references
```bash
gemini -p "[base prompt]. Analyze the following files: @./relative/path/to/attachment1 @./relative/path/to/attachment2. Do NOT modify any files." -y
```
Capture the output from the Bash tool result and write it to `${IDEATION_DIR}/gemini-ideation-${SESSION_ID}.md` using the Write tool.

Wait for all to complete. Read all output files.

If any model fails or times out, log the error and continue with remaining models.

---

### Step 3: Synthesize

Claude reads all raw responses and produces a unified synthesis:

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

Send the synthesis back to Codex and Gemini for their reactions. Each model sees ALL ideas (including their own) and the consensus tags.

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

**Codex** (if `HAS_CODEX`):
```bash
codex exec -s read-only -C "${PROJECT_ROOT}" -o "${IDEATION_DIR}/codex-counter-${SESSION_ID}.md" "[counter-review prompt]"
```

**Gemini** (if `HAS_GEMINI`):
```bash
gemini -p "[counter-review prompt]. Do NOT modify any files." -y
```
Capture the output from the Bash tool result and write it to `${IDEATION_DIR}/gemini-counter-${SESSION_ID}.md` using the Write tool.

**Claude** also performs its own counter-review natively — evaluating the synthesis critically, especially ideas from Codex and Gemini that Claude may have over- or under-weighted during synthesis.

Read all counter-review outputs.

---

### Step 5: Final Report

Claude produces the final report incorporating all counter-review feedback.

**Report structure:**

```markdown
# Ideation Report — [Topic Summary]

**Session:** [SESSION_ID]
**Date:** [date]
**Models:** [list of models that participated]

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
- Claude: ${IDEATION_DIR}/claude-ideation-${SESSION_ID}.md
- Codex: ${IDEATION_DIR}/codex-ideation-${SESSION_ID}.md
- Gemini: ${IDEATION_DIR}/gemini-ideation-${SESSION_ID}.md
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
- Claude is the **synthesizer**, not a privileged voice — its ideas are attributed and challengeable just like the others
- Codex model inherited from `~/.codex/config.toml` — do not hardcode `-m`
- Gemini model inherited from `~/.gemini/settings.json` (`general.model`) — do not hardcode `-m`
- Always use `-s read-only` for Codex — no file modifications
- Use `-y` for Gemini in non-interactive mode — prompt explicitly instructs "do NOT modify any files"
- If a model fails or times out, continue with remaining models (minimum: Claude alone)
- Use Read/Write tools for file operations — never `cp`, `mv`, or shell redirects
- **Never use `cd` in Bash** — use `-C <dir>` for codex/git, absolute paths elsewhere
- **Never use `$()` or pipe to `jq`** — run standalone, parse JSON natively
- Quote all bash variables: `"${VAR}"`
- If Codex CLI missing, suggest `npm install -g @openai/codex`
- If Gemini CLI missing, suggest `npm install -g @google/gemini-cli`
