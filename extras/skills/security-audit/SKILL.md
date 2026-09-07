---
name: security-audit
description: >
  Agent-agnostic multi-agent AI security review of the entire codebase.
  The primary driver coordinates native subagents and external reviewers with counter-review
  on every finding. Read-only, no code modifications. Use when the user
  wants a deep AI-powered security audit, full codebase security
  analysis, or says "audit security", "comprehensive security review",
  or "check the whole codebase for security issues".
---

# Security Audit (Agent-Agnostic Full-Codebase AI Analysis)

Orchestrate a multi-agent AI security review of the entire codebase. The **primary driver** is whichever agent is executing this skill: Claude Code, Codex App, or Codex CLI. It coordinates native subagents and optional external reviewers, performs a counter-review on every finding, and generates a comprehensive security report. **Read-only — no code modifications.**

## When to Invoke

- When the user runs `/security-audit` on any project
- When the user wants an AI-powered security audit of the full codebase (not just diffs)

## Prerequisites

Requires **git**. Optional reviewer channels: Claude, Codex, and native subagents. Missing reviewers do not block; record reduced coverage in the report.

---

## Options

- `effort=<fast|balanced|deep>` — default `balanced`. Maps to reasoning effort only; every driver inherits the user's configured model.
- `model=<fable|opus|sonnet|haiku>` — Claude model override for native subagents and the Claude reviewer channel.
- `budget=<usd>` — per-run `--max-budget-usd` for the Claude reviewer channel. No cap by default.

The mapping table, override rules, and cost notes are in [references/reviewer-contracts.md](references/reviewer-contracts.md). Every reviewer and lens returns the object in [references/findings-schema.md](references/findings-schema.md) with the severity enum `CRITICAL`, `HIGH`, `MEDIUM`, `LOW`. Print the resolved effort, model override, and budget at startup.

---

## Runtime Adapter

At startup, identify and store:

- `PRIMARY_DRIVER`: `claude-code`, `codex-app`, `codex-cli`, or `unknown`
- `REVIEWER_REGISTRY`: primary-native analysis, native subagents, external CLI reviewers, skipped reviewers, and independence notes

Detect `PRIMARY_DRIVER` from the active runtime:

| Signal | Primary driver |
|--------|----------------|
| Claude Code command context, or tools such as Task/Read/Write/Bash | `claude-code` |
| Codex desktop/app context | `codex-app` |
| Running under `codex exec` / Codex CLI | `codex-cli` |
| Ambiguous runtime | `unknown`; use neutral capabilities and ask only if behavior materially differs |

Reviewer defaults:

- Always run `primary-native` security analysis.
- Use native subagents for focused lenses when available.
- Claude primary: Codex CLI is the optional external reviewer. Skip a separate Claude CLI reviewer by default because it is same-family unless the user explicitly requests it.
- Codex primary: the Claude reviewer channel is the optional external reviewer; secondary Codex sessions must be labeled `secondary same-family review` and are skipped by default unless explicitly requested.

When Codex is the primary driver, external reviewer subprocesses (`claude` and optional secondary `codex`) require sandbox and approval settings that permit launching those commands and using their network-backed model sessions. If a subprocess is blocked by policy, mark that reviewer as skipped and continue.

By default, no external reviewer is required. A reviewer becomes required only when the user explicitly requests it. Advisory reviewer skips reduce confidence but do not block report generation.

---

## Agent Instructions

When invoked, execute the following phases sequentially.

---

## Phase 1: Preflight

### Step 1a: Verify Git Repo & Detect Project Root

```bash
git rev-parse --is-inside-work-tree
```
```bash
git rev-parse --show-toplevel
```

If not inside a git repo, stop: "Not a git repository. Run this from inside a project."

Store the toplevel path as `PROJECT_ROOT`. **Bash safety rules for the entire skill:**
- **Never use `cd`** — use absolute paths everywhere, `-C <dir>` for Codex
- **Never use `$()`** command substitution — run commands standalone, parse output natively
- **Never pipe to `jq`** — parse JSON natively in-context

### Step 1b: Generate Review ID

Generate a random 8-character hex string natively (not Bash). Store as `REVIEW_ID`.

### Step 1c: Set Up Review Directory

Set `REVIEW_DIR` to `.review/` in the project root (absolute path). Add `.review/` to `.gitignore` if missing. The directory is created automatically when the primary driver's file-write capability writes the first file into it — do NOT use `mkdir`.

### Step 1d: Detect Project Type

Scan the project root for indicators. Set `PROJECT_TYPE` to one or more of:

| Indicator | Type |
|-----------|------|
| `package.json` | node |
| `tsconfig.json` | typescript |
| `requirements.txt`, `pyproject.toml`, `setup.py` | python |
| `go.mod` | go |
| `Cargo.toml` | rust |
| `pom.xml`, `build.gradle` | java |
| `Dockerfile` | docker |
| `*.html`, `next.config.*`, `vite.config.*` | web |

Use the primary driver's file-read capability to check for these files — not Bash.

### Step 1e: Detect Reviewer Channels

Check available reviewer channels with standalone commands where applicable:

```bash
claude --version
```
```bash
codex --version
```

Set `HAS_CLAUDE_REVIEWER` and `HAS_CODEX` to true/false based on the primary driver and configured reviewer channels. If unavailable, warn and continue. If Codex is primary and Claude reviewer channel is unavailable, record that explicitly in `reviewerRegistry`.

### Step 1f: Initialize State File

Write state to `${REVIEW_DIR}/security-audit-state-${REVIEW_ID}.json`:

```json
{
  "reviewId": "<REVIEW_ID>",
  "primaryDriver": "<PRIMARY_DRIVER>",
  "projectRoot": "<PROJECT_ROOT>",
  "reviewDir": "<REVIEW_DIR>",
  "projectType": ["<detected types>"],
  "reviewerRegistry": [],
  "externalThreadIds": {},
  "phase": "preflight",
  "findings": [],
  "dispositions": []
}
```

**CRITICAL — Read and update this state file after every major step to guard against context compression. After compaction, the state file is the ONLY reliable source of truth.**

Also write the findings schema, with the `CRITICAL`, `HIGH`, `MEDIUM`, `LOW` severity enum, to `${REVIEW_DIR}/findings.schema.json`.

---

## Phase 2: AI Security Analysis

### Step 2a: Native Subagents

Launch the three lens agents that ship with this plugin **in parallel**: `code-reviewer`, `silent-failure-hunter`, and `type-design-analyzer` (dispatch rules in [references/reviewer-contracts.md](references/reviewer-contracts.md), "Native lens agents"). Under Codex primary without custom agents, run the same three prompts as primary-native passes and label them `primary-native`.

Prefix every prompt with "Repository root: ${PROJECT_ROOT}. Severity scale: CRITICAL, HIGH, MEDIUM, LOW. Return the findings object defined by this schema as your final message: [schema JSON]."

**1. `code-reviewer`**

Prompt: "Perform a security-focused review of the ENTIRE codebase (not just recent changes). Focus on:
- Injection vulnerabilities (SQL, command, XSS, template injection)
- Authentication and authorization flaws
- Sensitive data exposure (hardcoded secrets, PII in logs, unencrypted storage)
- Insecure defaults and misconfigurations
- Broken access control
- Path traversal and file inclusion
Report each finding with: severity (CRITICAL / HIGH / MEDIUM / LOW), file path, line number, vulnerability type, and description."

**2. `silent-failure-hunter`**

Prompt: "Perform a security-focused review of the ENTIRE codebase (not just recent changes). Focus on:
- Fail-open patterns (catch blocks that allow continued execution on security failures)
- Swallowed security exceptions (auth errors, permission checks, validation failures silently ignored)
- Missing error propagation in security-critical paths
- Silent fallback to insecure defaults when secure path fails
- Empty catch blocks around cryptographic or authentication operations
Report each finding with: severity (CRITICAL / HIGH / MEDIUM / LOW), file path, line number, vulnerability type, and description."

**3. `type-design-analyzer`**

Prompt: "Perform a security-focused review of the ENTIRE codebase (not just recent changes). Focus on:
- Type coercion vulnerabilities (loose equality, implicit conversions in security checks)
- Unsafe type casts or assertions that bypass type safety on untrusted data
- Data flow from untrusted sources (user input, API responses, environment variables) through the type system
- Missing input validation at system boundaries
- Types that fail to encode security invariants (e.g., sanitized vs raw strings)
Report each finding with: severity (CRITICAL / HIGH / MEDIUM / LOW), file path, line number, vulnerability type, and description."

Put the vulnerability type at the start of each finding's `title`.

### Step 2b: Primary-Native Analysis

While waiting for subagents or after they complete, the primary driver performs its own security analysis of the codebase. Focus on OWASP Top 10 categories mapped to the detected project type:

| OWASP Category | What to Check |
|----------------|---------------|
| A01: Broken Access Control | Auth checks, role validation, IDOR, path traversal |
| A02: Cryptographic Failures | Weak algorithms, hardcoded keys, missing encryption |
| A03: Injection | SQL, NoSQL, command, LDAP, XSS, template injection |
| A04: Insecure Design | Missing rate limiting, business logic flaws |
| A05: Security Misconfiguration | Debug mode, default credentials, unnecessary features |
| A06: Vulnerable Components | Known-vulnerable patterns, outdated API usage |
| A07: Auth Failures | Weak passwords, missing MFA, session issues |
| A08: Data Integrity Failures | Deserialization, unsigned updates, CI/CD trust |
| A09: Logging Failures | Missing audit logs, PII in logs, log injection |
| A10: SSRF | Unvalidated URLs, internal network access |

Also check (based on project type):
- **web**: CORS configuration, CSP headers, cookie flags, CSRF protection
- **node/typescript**: `eval()`, `child_process`, prototype pollution, ReDoS
- **python**: `pickle`, `exec()`, `os.system()`, SSTI
- **docker**: privileged containers, exposed ports, secrets in build args
- **All**: secrets in code, `.env` files committed, API keys, file upload handling, error message leakage

Use the primary driver's search and file-read capabilities to inspect security-relevant patterns. Record each finding with: severity, file, line, OWASP category, vulnerability type, description.

Update state file with all primary-native findings.

---

## Phase 3: External Security Reviewers

Run each available external reviewer from `REVIEWER_REGISTRY`. Skip unavailable reviewers and record the reason.

Launch external security reviewers in parallel when the runtime supports parallel tool calls or background commands:

- Claude Code: launch long-running CLI reviewers with background shell execution when available, and collect outputs at the sync point.
- Codex App / CLI: use the runtime's available parallel tool calls or background task mechanism. If unavailable, run reviewers sequentially and record `parallelism: unavailable`.
- All runtimes: wait for every launched reviewer before consolidating findings.

Read the state file to restore variables.

Run the Codex channel under Claude primary and the Claude channel under Codex primary, using the round-1 commands from [references/reviewer-contracts.md](references/reviewer-contracts.md) with the findings schema and this prompt substituted into `[PROMPT]`:

```text
Repository root: ${PROJECT_ROOT}. You are a security auditor. Perform a comprehensive security review of this entire codebase. Use read-only file access and read-only git commands only. Check for: injection vulnerabilities, authentication flaws, authorization bypasses, sensitive data exposure, cryptographic weaknesses, insecure configurations, SSRF, deserialization issues, and any other security concerns. Report each finding with severity CRITICAL, HIGH, MEDIUM, or LOW, the file path relative to the repository root, the line number, and a title that starts with the vulnerability type. Do not modify files. Return only the findings object.
```

Output files: `${REVIEW_DIR}/claude-security-round-1-${REVIEW_ID}.json` and `${REVIEW_DIR}/codex-security-round-1-${REVIEW_ID}.json`. This skill is single-pass, so store the session ids but do not resume them. A same-family second session runs only when the user asked for it and is labeled `secondary same-family review`.

Read each output file with the primary driver's file-read capability and add its findings to the state file.

---

## Phase 4: Consolidate & Counter-Review

### Step 4a: Deduplicate

Read the state file to restore all findings.

Combine findings from all sources: primary-native analysis, the three lens agents, and external reviewers. Compute fingerprints and deduplicate as described in [references/findings-schema.md](references/findings-schema.md). When duplicates are found, keep the highest severity and note which reviewers agreed.

### Step 4b: Counter-Review

Evaluate EVERY finding. Assign dispositions:

| Disposition | Meaning | Action |
|-------------|---------|--------|
| **agree** | Valid security issue | Include in report |
| **partial** | Valid but severity adjusted | Include with adjusted severity |
| **defer** | Needs more context to confirm | Flag for user |
| **reject** | False positive or not applicable | Must include rationale |

Present the counter-review table to the user:

```
## Security Audit Counter-Review

| # | Source | Severity | Vuln Type | File:Line | Disposition | Rationale |
|---|--------|----------|-----------|-----------|-------------|-----------|
| 1 | code-reviewer | CRITICAL | SQL Injection | src/db.ts:42 | agree | Unsanitized user input in query |
| 2 | silent-failure-hunter | HIGH | Fail-Open | src/auth.ts:15 | reject | Catch block correctly re-throws after logging |
```

Update state file with dispositions.

---

## Phase 5: Decision Gate

**Skip if there are no `reject` or `defer` dispositions.**

For each `reject` or `defer` finding, present to the user:

1. The original finding (source agent, severity, description)
2. Your counter-review rationale
3. Ask: "Include in report (agree), exclude (reject), or flag for follow-up (defer)?"

Wait for the user's decision on each item. Update dispositions in state file.

---

## Phase 6: Artifact Generation

Read the state file to restore all findings and dispositions.

Create the directory `docs/analysis/` if it doesn't exist using the primary driver's file-write capability.

Write the report to `${PROJECT_ROOT}/docs/analysis/security-audit-${REVIEW_ID}.md`:

```markdown
# Security Audit Report

**Review ID:** ${REVIEW_ID}
**Date:** YYYY-MM-DD HH:MM
**Scope:** Full codebase AI security analysis
**Project Type:** ${PROJECT_TYPE}

## Executive Summary

[2-3 sentence overview: total findings by severity, top concerns, overall risk posture]

## Methodology

This audit used multiple AI agents to analyze the full codebase for security vulnerabilities:

| Agent | Focus Area | Findings |
|-------|------------|----------|
| Primary driver (native) | OWASP Top 10, project-specific checks | N |
| Native code/security reviewer | Injection, auth, data exposure | N / Skipped |
| Native silent-failure hunter | Fail-open, swallowed exceptions | N / Skipped |
| Native type/design analyzer | Type coercion, unsafe casts, data flow | N / Skipped |
| Claude reviewer channel | Comprehensive audit | N / Skipped |
| Codex CLI | Comprehensive audit | N / Skipped |

Findings were deduplicated, counter-reviewed, and validated through a user decision gate.

## Reviewer Coverage

| Reviewer | Status | Independence | Notes |
|----------|--------|--------------|-------|
| [reviewer] | Ran / Skipped | independent / native / secondary same-family | [notes] |

## Critical Findings

| # | Vuln Type | File | Line | Description | OWASP |
|---|-----------|------|------|-------------|-------|
[One row per CRITICAL finding, or "No critical findings"]

## High Findings

| # | Vuln Type | File | Line | Description | OWASP |
|---|-----------|------|------|-------------|-------|
[One row per HIGH finding, or "No high findings"]

## Medium Findings

| # | Vuln Type | File | Line | Description | OWASP |
|---|-----------|------|------|-------------|-------|
[One row per MEDIUM finding, or "No medium findings"]

## Low Findings

| # | Vuln Type | File | Line | Description | OWASP |
|---|-----------|------|------|-------------|-------|
[One row per LOW finding, or "No low findings"]

## Counter-Review Summary

| Disposition | Count |
|-------------|-------|
| agree | N |
| partial | N |
| defer | N |
| reject | N |

### Rejected Findings

| # | Source | Original Finding | Rejection Rationale |
|---|--------|-----------------|---------------------|
[One row per rejected finding, or "None"]

### Deferred Findings

| # | Source | Finding | Reason for Deferral |
|---|--------|---------|---------------------|
[One row per deferred finding, or "None"]

## OWASP Top 10 Coverage

| Category | Checked | Findings |
|----------|---------|----------|
| A01: Broken Access Control | Yes | N |
| A02: Cryptographic Failures | Yes | N |
| A03: Injection | Yes | N |
| A04: Insecure Design | Yes | N |
| A05: Security Misconfiguration | Yes | N |
| A06: Vulnerable Components | Yes | N |
| A07: Authentication Failures | Yes | N |
| A08: Data Integrity Failures | Yes | N |
| A09: Logging & Monitoring Failures | Yes | N |
| A10: SSRF | Yes | N |

## Prioritized Recommendations

1. [Most critical action item]
2. [Second priority]
3. [...]

## Disclaimer

This is an AI-powered analysis and may contain false positives or miss vulnerabilities. It is not a substitute for professional penetration testing or a formal security audit. Secret values are never included in this report — only types and locations.
```

---

## Phase 7: Present

Leave `.review/` in place. It is gitignored and every file carries the review id, so nothing needs deleting.

### Step 7a: Present Results

Present to the user:

1. **Summary**: Total findings by severity (CRITICAL / HIGH / MEDIUM / LOW)
2. **Top concerns**: Critical and high items highlighted
3. **Artifact path**: `docs/analysis/security-audit-${REVIEW_ID}.md`
4. **Complement**: "For tool-based scanning (SAST, dependency audit, secret detection), run `/security-scan`."

---

## Rules

- `.review/` for temp files — auto-create via the primary driver's file-write capability, add to `.gitignore` if missing
- **Read-only analysis** — do NOT modify any source code
- State file read/updated after every major step — survives context compaction
- **Secret values NEVER written** to the artifact or presented to the user — redact always
- Quote all bash variables: `"${VAR}"`
- **Never use `cd`** — use absolute paths everywhere, `-C <dir>` for Codex
- **Never use `$()` or pipe to `jq`** — run standalone, parse JSON natively
- Every driver inherits the user's configured model; `effort=` maps to reasoning effort only, `model=` overrides Claude only
- External reviewer commands, flags, output parsing, and failure handling come from `references/reviewer-contracts.md`; every reviewer and lens returns the `references/findings-schema.md` object
- Required external reviewers default to none; only user-explicit reviewers are required
- Sandbox or network policy blocks on advisory reviewers degrade coverage but do not block report generation
- Do NOT commit the report automatically — let the user decide
- Never spawn a subprocess of the primary driver to perform analysis or edits; external reviewer CLIs must stay read-only
- Run each Bash command as a standalone call — never chain with `&&` or `$()`
