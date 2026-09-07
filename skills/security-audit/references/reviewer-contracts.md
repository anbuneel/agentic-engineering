# Reviewer Contracts

Shared by `multi-agent-code-review`, `multi-agent-plan-review`, `multi-agent-ideate`, and `security-audit`. Each skill carries an identical copy in its `references/` directory so it stays self-contained; edit all copies together.

Every flag here was verified against Claude Code 2.1.263 and Codex CLI 0.150.1.

## Effort and model

`effort=<fast|balanced|deep>` is the cross-driver option. Default `balanced`. Effort never selects a model tier: every driver inherits the model the user configured (Claude Code settings for Claude, `~/.codex/config.toml` for Codex).

| Effort | Claude CLI and native subagents | Codex CLI |
|--------|----------------------------------|-----------|
| `fast` | inherit model; add `--effort low` | add `-c model_reasoning_effort="low"` |
| `balanced` | inherit model and configured effort; add nothing | add nothing |
| `deep` | inherit model; add `--effort xhigh` | add `-c model_reasoning_effort="xhigh"` |

Overrides:

- `model=<fable|opus|sonnet|haiku>` changes the Claude model only. Pass it as `--model <alias>` on the Claude CLI and use the same alias when dispatching native subagents. Never pass `-m` to Codex.
- `budget=<usd>` adds `--max-budget-usd <usd>` to every Claude CLI run. There is no cap by default. A headless Claude run on Fable 5.1 costs roughly 0.3 to 0.7 USD before any review work (system prompt cache write), so a cap under 2 USD aborts before the review starts.

Print the resolved effort, any model override, and any budget at startup.

## Read-only guarantees

External reviewers never modify files.

- Claude CLI: `--permission-mode plan --permission-prompts none --allowedTools <read-only list> --disallowedTools "Edit" "Write" "MultiEdit"`. `--permission-prompts none` denies anything that would prompt instead of leaving it to the user's settings.
- Codex CLI: `-s read-only`.
- Both: the prompt says "Do not modify files."

## Working directory

Claude CLI has no `-C`. Launch it with the shell command working directory set to `PROJECT_ROOT`. If the runtime cannot set cwd, add `--add-dir "${PROJECT_ROOT}"` and put the root in the prompt. Codex takes `-C "${PROJECT_ROOT}"` on `codex exec`; `codex exec resume` inherits it and rejects `-C` and `-s`.

Never use `cd`, `$()`, or pipes to `jq`. Run each command standalone and parse its output natively.

## Claude reviewer channel

Used when Codex is the primary driver. When Claude is primary, a second Claude session is same-family: skip it by default, or run it labeled `secondary same-family review` if the user asked for it.

Round 1:

```bash
claude -p "[PROMPT]" --permission-mode plan --permission-prompts none --allowedTools "Read" "Grep" "Glob" "Bash(git diff:*)" "Bash(git log:*)" "Bash(git status:*)" "Bash(git grep:*)" --disallowedTools "Edit" "Write" "MultiEdit" --output-format json
```

Append as resolved: `--json-schema '<schema JSON>'` when the skill uses the findings schema, `--effort <level>`, `--model <alias>`, `--max-budget-usd <usd>`.

Parse the single JSON object natively:

| Field | Use |
|-------|-----|
| `session_id` | store as `externalThreadIds.claude` in the state file immediately |
| `structured_output` | the parsed object when `--json-schema` was given; write it to `${REVIEW_DIR}/claude-<purpose>-round-<N>-${REVIEW_ID}.json` |
| `result` | the text answer when no schema was given; write it to `${REVIEW_DIR}/claude-<purpose>-round-<N>-${REVIEW_ID}.md` |
| `is_error`, `subtype` | anything other than `false` and `success` means the reviewer failed; record the `errors` array in the registry and continue |
| `total_cost_usd` | record in the registry entry |

Round 2 and later: the same command plus `--resume "${CLAUDE_SESSION_ID}"`, with a prompt that summarises what changed and asks whether prior findings are resolved. If resume fails, run a fresh round-1 command with the prior-round context in the prompt and store the new `session_id`.

## Codex reviewer channel

Used when Claude is the primary driver. When Codex is primary, a second Codex session is same-family: skip it by default, or run it labeled `secondary same-family review` if the user asked for it.

Round 1:

```bash
codex exec --json -s read-only -C "${PROJECT_ROOT}" --output-schema "${REVIEW_DIR}/findings.schema.json" -o "${REVIEW_DIR}/codex-<purpose>-round-1-${REVIEW_ID}.json" "[PROMPT]"
```

Append `-c model_reasoning_effort="<level>"` when effort resolves to one. Omit `--output-schema` for free-form outputs (ideation) and give `-o` a `.md` path.

- The first JSONL line on stdout is `{"type":"thread.started","thread_id":"<UUID>"}`. Store `thread_id` as `externalThreadIds.codex` immediately. That is the only reason to keep `--json`.
- `-o` writes the final message to the file. Read it with the file tool. Do not scrape `item.completed` events.
- If stdout contains `turn.failed`, the reviewer failed; record the message and continue. The message `requires a newer version of Codex` means the CLI is older than the configured model: record `skipped: Codex CLI outdated, run npm install -g @openai/codex` and continue.

Round 2 and later:

```bash
codex exec resume "${CODEX_THREAD_ID}" --json --output-schema "${REVIEW_DIR}/findings.schema.json" -o "${REVIEW_DIR}/codex-<purpose>-round-<N>-${REVIEW_ID}.json" "[PROMPT]"
```

No `-s`, no `-C`, no `-a`. If resume fails, run a fresh round-1 command with the prior-round context in the prompt and store the new `thread_id`.

## Native lens agents

Three review agents ship with the plugin under `agents/`: `code-reviewer`, `silent-failure-hunter`, and `type-design-analyzer`. Each is read-only and takes the scope, severity scale, and output format from the task prompt.

- Claude primary: dispatch each with the Agent tool by name (use the `ae:` prefix if the runtime namespaces plugin agents). Apply `model=` if given. Launch all three in one parallel batch. Ask each to return the findings schema object as its final message.
- Codex primary: if Codex custom agents are configured, use them with the same prompts. Otherwise run the three prompts as primary-native passes and label them `primary-native`, not independent.

## Independence and requirement rules

- Reviewers are advisory by default. A reviewer is required only when the user names it.
- An advisory reviewer that is unavailable, policy-blocked, or fails is recorded as skipped with the reason and does not block convergence; note the degraded coverage in the artifact.
- A required reviewer that is unavailable stops for a user decision: continue degraded, retry, or stop.
- Cross-family reviewers (Claude under Codex primary, Codex under Claude primary) are `independent`. A second session of the primary driver's own family is `secondary same-family review`.
- Under Codex primary, launching `claude` needs a sandbox and approval policy that permits the subprocess and its network access. If policy blocks it, record `skipped: policy` and continue.
- The primary driver counter-reviews every finding regardless of source or verdict. A reviewer verdict never bypasses that.

## Output files

Everything goes under `${REVIEW_DIR}` (`.review/` in the project root, gitignored). Write files with the driver's file tool. Codex `-o` is a flag, not a shell redirect, and is the one exception. Never use `>`, `cp`, or `mv`.
