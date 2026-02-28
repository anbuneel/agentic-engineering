# Security Audit (Full-Codebase AI Analysis)

Orchestrate a multi-agent AI security review of the entire codebase. Claude coordinates pr-review-toolkit agents and optionally Codex CLI, performs a counter-review on every finding, and generates a comprehensive security report. **Read-only — no code modifications.**

## When to Invoke

- When the user runs `/security-audit` on any project
- When the user wants an AI-powered security audit of the full codebase (not just diffs)

## Prerequisites

Requires **git**. Optional: [Codex CLI](https://github.com/openai/codex) for additional AI perspective (`npm install -g @openai/codex`).

---

## Agent Instructions

When invoked, execute the following phases sequentially.

---

## Phase 1: Preflight

### Step 1a: Verify Git Repo & Detect Project Root

```bash
git rev-parse --is-inside-work-tree && git rev-parse --show-toplevel
```

If not inside a git repo, stop: "Not a git repository. Run this from inside a project."

Store the toplevel path as `PROJECT_ROOT`. Use absolute paths throughout — **never use `cd`**.

### Step 1b: Generate Review ID

Generate a random 8-character hex string natively (not Bash). Store as `REVIEW_ID`.

### Step 1c: Set Up Review Directory

Set `REVIEW_DIR` to `.review/` in the project root (absolute path). Add `.review/` to `.gitignore` if missing. The directory is created automatically when the Write tool writes the first file into it — do NOT use `mkdir`.

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

Use Read tool to check for these files — not Bash.

### Step 1e: Detect Codex CLI

```bash
codex --version
```

Set `HAS_CODEX` to true/false. If unavailable, warn: "Codex CLI not found. Continuing with Claude + pr-review-toolkit agents only. Install: `npm install -g @openai/codex`"

### Step 1f: Initialize State File

Write state to `${REVIEW_DIR}/security-audit-state-${REVIEW_ID}.json`:

```json
{
  "reviewId": "<REVIEW_ID>",
  "projectRoot": "<PROJECT_ROOT>",
  "reviewDir": "<REVIEW_DIR>",
  "projectType": ["<detected types>"],
  "hasCodex": true/false,
  "phase": "preflight",
  "findings": [],
  "dispositions": []
}
```

**CRITICAL — Read and update this state file after every major step to guard against context compression. After compaction, the state file is the ONLY reliable source of truth.**

---

## Phase 2: AI Security Analysis

### Step 2a: pr-review-toolkit Agents

Launch 3 pr-review-toolkit agents **in parallel** using the Task tool:

**1. `pr-review-toolkit:code-reviewer`**

Prompt: "Perform a security-focused review of the ENTIRE codebase (not just recent changes). Focus on:
- Injection vulnerabilities (SQL, command, XSS, template injection)
- Authentication and authorization flaws
- Sensitive data exposure (hardcoded secrets, PII in logs, unencrypted storage)
- Insecure defaults and misconfigurations
- Broken access control
- Path traversal and file inclusion
Report each finding with: severity (CRITICAL / HIGH / MEDIUM / LOW), file path, line number, vulnerability type, and description."

**2. `pr-review-toolkit:silent-failure-hunter`**

Prompt: "Perform a security-focused review of the ENTIRE codebase (not just recent changes). Focus on:
- Fail-open patterns (catch blocks that allow continued execution on security failures)
- Swallowed security exceptions (auth errors, permission checks, validation failures silently ignored)
- Missing error propagation in security-critical paths
- Silent fallback to insecure defaults when secure path fails
- Empty catch blocks around cryptographic or authentication operations
Report each finding with: severity (CRITICAL / HIGH / MEDIUM / LOW), file path, line number, vulnerability type, and description."

**3. `pr-review-toolkit:type-design-analyzer`**

Prompt: "Perform a security-focused review of the ENTIRE codebase (not just recent changes). Focus on:
- Type coercion vulnerabilities (loose equality, implicit conversions in security checks)
- Unsafe type casts or assertions that bypass type safety on untrusted data
- Data flow from untrusted sources (user input, API responses, environment variables) through the type system
- Missing input validation at system boundaries
- Types that fail to encode security invariants (e.g., sanitized vs raw strings)
Report each finding with: severity (CRITICAL / HIGH / MEDIUM / LOW), file path, line number, vulnerability type, and description."

### Step 2b: Claude Native Analysis

While waiting for agents or after they complete, perform your own security analysis of the codebase. Focus on OWASP Top 10 categories mapped to the detected project type:

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

Use Glob and Grep to search for security-relevant patterns. Use Read to examine suspicious files. Record each finding with: severity, file, line, OWASP category, vulnerability type, description.

Update state file with all Claude findings.

---

## Phase 3: Codex CLI Security Review

**Skip this entire phase if `HAS_CODEX` is false.**

Read the state file to restore variables.

```bash
codex exec -s read-only -C "${PROJECT_ROOT}" "You are a security auditor. Perform a comprehensive security review of this entire codebase. Check for: injection vulnerabilities, authentication flaws, authorization bypasses, sensitive data exposure, cryptographic weaknesses, insecure configurations, SSRF, deserialization issues, and any other security concerns. For each finding report: SEVERITY (CRITICAL/HIGH/MEDIUM/LOW), file path, line number, vulnerability type, and detailed description. End with a count of findings by severity."
```

Note: Codex output goes to stdout — capture from Bash tool result. Parse findings from the output.

Update state file with Codex findings.

---

## Phase 4: Consolidate & Counter-Review

### Step 4a: Deduplicate

Read the state file to restore all findings.

Combine findings from all sources (pr-review-toolkit agents, Claude native, Codex CLI). Deduplicate using `file:line:vulnerabilityType` fingerprints. When duplicates found, keep the highest severity and note which agents agreed.

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

Create the directory `docs/analysis/` if it doesn't exist (use Write tool — writing the file auto-creates parent dirs).

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
| Claude (native) | OWASP Top 10, project-specific checks | N |
| pr-review-toolkit:code-reviewer | Injection, auth, data exposure | N |
| pr-review-toolkit:silent-failure-hunter | Fail-open, swallowed exceptions | N |
| pr-review-toolkit:type-design-analyzer | Type coercion, unsafe casts, data flow | N |
| Codex CLI | Comprehensive audit | N / Skipped |

Findings were deduplicated, counter-reviewed, and validated through a user decision gate.

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

## Phase 7: Cleanup & Present

### Step 7a: Cleanup

Delete the state file:

Delete the state file: `rm -f "${REVIEW_DIR}/security-audit-state-${REVIEW_ID}.json"` (single Bash command, permission prompt expected).

### Step 7b: Present Results

Present to the user:

1. **Summary**: Total findings by severity (CRITICAL / HIGH / MEDIUM / LOW)
2. **Top concerns**: Critical and high items highlighted
3. **Artifact path**: `docs/analysis/security-audit-${REVIEW_ID}.md`
4. **Complement**: "For tool-based scanning (SAST, dependency audit, secret detection), run `/security-scan`."

---

## Rules

- `.review/` for temp files — auto-create via Write tool, add to `.gitignore` if missing
- **Read-only analysis** — do NOT modify any source code
- State file read/updated after every major step — survives context compaction
- **Secret values NEVER written** to the artifact or presented to the user — redact always
- Quote all bash variables: `"${VAR}"`
- **Never use `cd`** — use absolute paths everywhere, `-C <dir>` for Codex
- **Never use `$()` or pipe to `jq`** — run standalone, parse JSON natively
- Codex model inherited from `~/.codex/config.toml` — do not hardcode `-m`
- Always `-s read-only` for Codex
- Do NOT commit the report automatically — let the user decide
- Fix code via Edit/Write tools — NEVER spawn `claude -p` or Claude subprocess
- **Minimize permission prompts** — combine related Bash commands (e.g., preflight checks) into single calls. Only keep separate commands where individual exit-code handling is needed.
