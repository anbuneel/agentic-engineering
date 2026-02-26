# Security Scan

Run SAST, dependency vulnerability, and secret detection scans against the entire codebase. Generates a consolidated security report.

## When to Invoke

- When the user runs `/security-scan` on any project
- When the user wants a security audit before shipping or merging

## Prerequisites

Requires **git**. At least one of these scanning tools must be installed:

- [Semgrep](https://semgrep.dev/) — SAST scanner (`pip install semgrep` or `brew install semgrep`)
- [Gitleaks](https://github.com/gitleaks/gitleaks) — secret detection (`brew install gitleaks` or download from releases)
- npm (for `npm audit`) — only runs if `package.json` exists in the project root

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

### Step 1b: Generate Scan ID

Generate a random 8-character hex string natively (not Bash). Store as `SCAN_ID`.

### Step 1c: Set Up Review Directory

Set `REVIEW_DIR` to `.review/` in the project root (absolute path). Add `.review/` to `.gitignore` if missing. The directory is created automatically when the Write tool writes the first file into it — do NOT use `mkdir`.

### Step 1d: Detect Available Tools

Check which scanning tools are installed in a single command:

```bash
semgrep --version 2>/dev/null && echo "SEMGREP_OK" || echo "SEMGREP_MISSING"; gitleaks version 2>/dev/null && echo "GITLEAKS_OK" || echo "GITLEAKS_MISSING"
```

Check if `package.json` exists in the project root (use Read tool, not Bash).

Track availability:
- `HAS_SEMGREP`: true/false based on command success
- `HAS_GITLEAKS`: true/false based on command success
- `HAS_NPM_AUDIT`: true/false based on `package.json` existence

For each unavailable tool, warn the user with install instructions:

| Tool | Install |
|------|---------|
| Semgrep | `pip install semgrep` or `brew install semgrep` |
| Gitleaks | `brew install gitleaks` or download from [releases](https://github.com/gitleaks/gitleaks/releases) |
| npm audit | Requires `package.json` in project root |

If **zero** tools are available, stop: "No scanning tools available. Install at least one: semgrep, gitleaks, or add a package.json for npm audit."

---

## Phase 2: Scan

Run each available tool sequentially. Skip unavailable tools.

### Step 2a: SAST — Semgrep

**Skip if `HAS_SEMGREP` is false.**

```bash
semgrep scan --config auto --json --output "${REVIEW_DIR}/semgrep-${SCAN_ID}.json" "${PROJECT_ROOT}"
```

Note: Semgrep may return exit code 1 if it finds issues — this is expected, not an error. Only treat non-zero exit as failure if stderr indicates an actual error (e.g., config not found, crash).

Parse JSON output natively (Read the output file, parse in-context — no `jq`, no `$()`).

Extract from each result:
- Rule ID (`check_id`)
- Severity (`extra.severity`: ERROR / WARNING / INFO)
- File path (`path`)
- Line number (`start.line`)
- Message (`extra.message`)

Store findings as `SEMGREP_FINDINGS` with count.

### Step 2b: Dependency Audit — npm audit

**Skip if `HAS_NPM_AUDIT` is false.**

```bash
npm audit --json --prefix "${PROJECT_ROOT}" > "${REVIEW_DIR}/npm-audit-${SCAN_ID}.json" 2>&1
```

Note: `npm audit` returns exit code 1 when vulnerabilities are found — this is expected. Only treat as failure if the JSON output is not parseable.

Parse JSON output natively (Read the output file, parse in-context).

Extract from each vulnerability:
- Package name
- Severity (critical / high / moderate / low)
- Vulnerability title
- Fix available (yes/no)

Store findings as `NPM_FINDINGS` with count.

### Step 2c: Secret Detection — Gitleaks

**Skip if `HAS_GITLEAKS` is false.**

```bash
gitleaks detect --source "${PROJECT_ROOT}" --report-format json --report-path "${REVIEW_DIR}/gitleaks-${SCAN_ID}.json"
```

Note: Gitleaks returns exit code 1 when leaks are found — this is expected.

Parse JSON output natively (Read the output file, parse in-context).

Extract from each finding:
- Rule description (`Description`)
- File path (`File`)
- Line number (`StartLine`)
- Secret type (`RuleID`)

**CRITICAL: NEVER extract, store, or write the actual secret value (`Secret` field). Only capture type and location.**

Store findings as `GITLEAKS_FINDINGS` with count.

---

## Phase 3: Artifact Generation

Create the directory `docs/analysis/` if it doesn't exist (use Write tool — writing the file auto-creates parent dirs).

Write the report to `${PROJECT_ROOT}/docs/analysis/security-scan-${SCAN_ID}.md`:

```markdown
# Security Scan Report

**Scan ID:** ${SCAN_ID}
**Date:** YYYY-MM-DD HH:MM
**Scope:** Full codebase

## Tools Run

| Tool | Status | Findings |
|------|--------|----------|
| Semgrep (SAST) | Ran / Skipped (not installed) | N |
| npm audit | Ran / Skipped (no package.json) | N |
| Gitleaks (secrets) | Ran / Skipped (not installed) | N |

## Summary

[Total findings count, breakdown by severity, top concern highlighted]

## SAST Findings (Semgrep)

| # | Severity | Rule | File | Line | Description |
|---|----------|------|------|------|-------------|
[One row per finding, or "No findings" if clean, or "Skipped — semgrep not installed" if skipped]

## Dependency Vulnerabilities (npm audit)

| # | Severity | Package | Vulnerability | Fix Available |
|---|----------|---------|---------------|---------------|
[One row per finding, or "No findings" if clean, or "Skipped — no package.json" if skipped]

## Secrets Detected (Gitleaks)

| # | Type | File | Line | Rule |
|---|------|------|------|------|
[One row per finding, or "No findings" if clean, or "Skipped — gitleaks not installed" if skipped]

(Secret values NEVER included — only type and location)

## Recommendations

[Prioritized action items based on findings:
- Critical/high severity items first
- Secrets should always be rotated immediately
- Dependency fixes with available patches
- SAST findings by severity]

## Skipped Tools

[For each tool that was not available, list:
- Tool name
- Why it was skipped
- Install instructions]
```

---

## Phase 4: Cleanup

Delete all temporary JSON files from `.review/` in a single command (only lists files for tools that actually ran):

```bash
rm -f "${REVIEW_DIR}/semgrep-${SCAN_ID}.json" "${REVIEW_DIR}/npm-audit-${SCAN_ID}.json" "${REVIEW_DIR}/gitleaks-${SCAN_ID}.json"
```

---

## Phase 5: Present Results

Present to the user:

1. Summary: total findings by severity across all tools
2. Top concerns (critical/high items highlighted)
3. Artifact path: `docs/analysis/security-scan-${SCAN_ID}.md`
4. Any skipped tools with install guidance

---

## Rules

- `.review/` for temp files — auto-create via Write tool, add to `.gitignore` if missing
- Parse all JSON natively — no `jq`, no `$()`, no pipes for JSON processing
- **Never use `cd`** — use absolute paths everywhere
- **Secret values NEVER written** to the artifact or presented to the user — redact always, only show type and location
- Quote all bash variables: `"${VAR}"`
- Non-zero exit codes from scanning tools are expected when findings exist — check stderr for actual errors
- **Minimize permission prompts** — combine related Bash commands (e.g., preflight checks, cleanup) into single calls. Only keep scan commands separate since each tool needs individual exit-code handling.
- Do NOT commit the scan report automatically — let the user decide
- Do NOT modify any source code — this skill is read-only analysis
