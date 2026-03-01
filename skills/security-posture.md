# Security Posture Check

Run a fast security hygiene baseline check against a project's infrastructure and configuration. Produces a scorecard with PASS / FAIL / N/A per check and a letter grade. **Read-only — no code modifications.**

## When to Invoke

- When the user runs `/security-posture` on any project
- When the user wants a quick check of security infrastructure before shipping

## Prerequisites

Requires **git**. Optional: [GitHub CLI (`gh`)](https://cli.github.com/) for branch protection checks.

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

Store the toplevel path as `PROJECT_ROOT`. **Bash safety rules for the entire skill:**
- **Never use `cd`** — use absolute paths everywhere
- **Never use `$()`** command substitution — run commands standalone, parse output natively
- **Never pipe to `jq`** — parse JSON natively in-context

### Step 1b: Generate Scan ID

Generate a random 8-character hex string natively (not Bash). Store as `SCAN_ID`.

### Step 1c: Detect Project Type

Scan the project root for indicators. Set flags:

| Indicator | Flag |
|-----------|------|
| `package.json` or `tsconfig.json` | `IS_NODE` / `IS_TYPESCRIPT` |
| `requirements.txt`, `pyproject.toml`, `setup.py` | `IS_PYTHON` |
| `go.mod` | `IS_GO` |
| `Cargo.toml` | `IS_RUST` |
| `Dockerfile` | `HAS_DOCKER` |
| `*.html`, `next.config.*`, `vite.config.*`, `angular.json` | `IS_WEB` |

Use Read/Glob tools to check — not Bash.

### Step 1d: Detect GitHub CLI

```bash
gh auth status
```

Set `HAS_GH` to true/false. If unavailable, note: "GitHub CLI not available — branch protection check will be N/A."

---

## Phase 2: Run Checks

Run all 16 checks sequentially. For each, record: check number, category, name, result (PASS / FAIL / N/A), and details.

---

### Category 1: Secret Management

#### Check 1.1: Gitignore Covers Secrets

Read `.gitignore` in the project root using the Read tool.

- **PASS**: `.gitignore` exists AND contains patterns for at least 3 of: `.env`, `*.key`, `*.pem`, `credentials`, `*.secret`, `.env.*`, `*.p12`, `*.pfx`
- **FAIL**: `.gitignore` missing or doesn't cover secrets
- Details: list which patterns are present/missing

#### Check 1.2: No Secrets in Git History

```bash
git log --all --diff-filter=A --name-only --pretty=format: -- "*.env" ".env" ".env.*" "*.key" "*.pem" "*.p12" "*.pfx" "credentials.json" "serviceAccountKey.json"
```

- **PASS**: No output (no secret files ever added)
- **FAIL**: Files listed (secret files were committed at some point)
- Details: list the files found

#### Check 1.3: Pre-commit Secret Detection Hook

Check for pre-commit hooks that include secret detection. Use Glob and Read:

1. Check `.pre-commit-config.yaml` for `detect-secrets`, `gitleaks`, or `trufflehog`
2. Check `.husky/pre-commit` for secret scanning commands
3. Check `.git/hooks/pre-commit` for secret scanning commands
4. Check `lefthook.yml` for secret scanning

- **PASS**: Any secret detection hook configured
- **FAIL**: No secret detection in pre-commit hooks
- Details: which hook system and tool detected, or "none found"

---

### Category 2: Dependency Management

#### Check 2.1: Lock File Exists

Use Glob to check for any of: `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `bun.lockb`, `Cargo.lock`, `go.sum`, `poetry.lock`, `Pipfile.lock`, `Gemfile.lock`, `composer.lock`

- **PASS**: At least one lock file found
- **FAIL**: No lock file found
- **N/A**: No package manager detected
- Details: which lock file(s) found

#### Check 2.2: Automated Dependency Updates

Use Glob to check for any of:
- `.github/dependabot.yml` or `.github/dependabot.yaml`
- `renovate.json`, `renovate.json5`, `.renovaterc`, `.renovaterc.json`

- **PASS**: Dependabot or Renovate config found
- **FAIL**: No automated dependency update tool configured
- Details: which tool detected

---

### Category 3: CI/CD Security

#### Check 3.1: CI Configuration Exists

Use Glob to check for any of: `.github/workflows/*.yml`, `.github/workflows/*.yaml`, `.gitlab-ci.yml`, `.circleci/config.yml`, `Jenkinsfile`, `.travis.yml`, `azure-pipelines.yml`, `bitbucket-pipelines.yml`

- **PASS**: CI config found
- **FAIL**: No CI configuration detected
- Details: which CI system detected

#### Check 3.2: CI Has Security Scanning

**N/A if Check 3.1 is FAIL.**

Read all CI config files found in Check 3.1. Search for any of: `semgrep`, `snyk`, `trivy`, `codeql`, `gitleaks`, `trufflehog`, `bandit`, `gosec`, `safety`, `npm audit`, `yarn audit`, `cargo audit`, `dependabot`, `security`

- **PASS**: Security scanning step found in CI
- **FAIL**: No security scanning in CI pipelines
- Details: which tools/steps detected

#### Check 3.3: Branch Protection Enabled

**N/A if `HAS_GH` is false.**

Resolve owner/repo and default branch:

```bash
gh repo view --json nameWithOwner,defaultBranchRef
```

Parse JSON natively to extract `{owner}/{repo}` and the default branch name.

```bash
gh api repos/{owner}/{repo}/branches/{default_branch}/protection
```

Parse JSON natively — do NOT use `--jq`.

- **PASS**: Branch protection rules exist (non-404 response)
- **FAIL**: No branch protection on default branch (404 response)
- **N/A**: GitHub CLI not available or not a GitHub repo
- Details: protection status summary

---

### Category 4: Security Documentation

#### Check 4.1: SECURITY.md Exists

Use Glob: `**/SECURITY.md` (case-insensitive check — also try `security.md`)

- **PASS**: `SECURITY.md` found
- **FAIL**: No security policy document
- Details: file path if found

#### Check 4.2: Security Reporting Instructions

**N/A if Check 4.1 is FAIL.**

Read `SECURITY.md`. Check for contact information or reporting instructions (email address, form URL, or clear reporting process).

- **PASS**: Reporting instructions present
- **FAIL**: `SECURITY.md` exists but lacks reporting instructions
- Details: summary of what's included

---

### Category 5: Code Security

#### Check 5.1: Security Linting Configured

Check based on project type:

- **Node/TS**: `eslint-plugin-security` in `package.json` devDependencies or eslint config
- **Python**: `bandit` in requirements/pyproject, or `.bandit` config file
- **Go**: `gosec` in CI or Makefile
- **Rust**: `cargo-audit` in CI or config

Use Read/Glob to check these files.

- **PASS**: Security linting tool configured for the project type
- **FAIL**: No security linting configured
- **N/A**: Project type not recognized or no applicable linting tool
- Details: which tool detected

#### Check 5.2: TypeScript Strict Mode

**N/A if `IS_TYPESCRIPT` is false.**

Read `tsconfig.json`. Check for `"strict": true`.

- **PASS**: Strict mode enabled
- **FAIL**: Strict mode not enabled
- Details: current strict setting

#### Check 5.3: CSP Headers Configured

**N/A if `IS_WEB` is false.**

Search for Content Security Policy configuration. Use Grep to search for `content-security-policy`, `CSP`, `helmet` (Node), `csp` in config files, middleware, and HTML meta tags.

- **PASS**: CSP configuration found
- **FAIL**: No CSP headers detected
- Details: where CSP is configured

---

### Category 6: Container Security

**All checks N/A if `HAS_DOCKER` is false.**

Read all Dockerfiles found via Glob: `**/Dockerfile*`

#### Check 6.1: Non-Root User

Check for `USER` directive in Dockerfile(s) that sets a non-root user.

- **PASS**: Non-root user configured
- **FAIL**: Running as root (no USER directive or USER root)
- Details: USER setting found

#### Check 6.2: Multi-Stage Build

Check for multiple `FROM` directives in Dockerfile(s).

- **PASS**: Multi-stage build used
- **FAIL**: Single-stage build
- Details: number of stages

#### Check 6.3: Specific Base Image Tags

Check that `FROM` directives use specific tags (not `:latest` or tag-less).

- **PASS**: All base images use specific tags
- **FAIL**: At least one base image uses `:latest` or no tag
- Details: list base images with their tags

---

## Phase 3: Scoring

Calculate the score:

1. Count PASS and FAIL results (exclude N/A)
2. Score = PASS / (PASS + FAIL) × 100
3. Assign grade:

| Score | Grade |
|-------|-------|
| 90-100% | A |
| 80-89% | B |
| 70-79% | C |
| 60-69% | D |
| < 60% | F |

---

## Phase 4: Artifact Generation

Create the directory `docs/analysis/` if it doesn't exist (use Write tool — writing the file auto-creates parent dirs).

Write the report to `${PROJECT_ROOT}/docs/analysis/security-posture-${SCAN_ID}.md`:

```markdown
# Security Posture Report

**Scan ID:** ${SCAN_ID}
**Date:** YYYY-MM-DD HH:MM
**Scope:** Security infrastructure and configuration
**Grade:** ${GRADE} (${SCORE}%)

## Summary

| Result | Count |
|--------|-------|
| PASS | N |
| FAIL | N |
| N/A | N |

## Scorecard

### 1. Secret Management

| # | Check | Result | Details |
|---|-------|--------|---------|
| 1.1 | Gitignore covers secrets | PASS/FAIL | [details] |
| 1.2 | No secrets in git history | PASS/FAIL | [details] |
| 1.3 | Pre-commit secret detection | PASS/FAIL | [details] |

### 2. Dependency Management

| # | Check | Result | Details |
|---|-------|--------|---------|
| 2.1 | Lock file exists | PASS/FAIL/N/A | [details] |
| 2.2 | Automated dependency updates | PASS/FAIL | [details] |

### 3. CI/CD Security

| # | Check | Result | Details |
|---|-------|--------|---------|
| 3.1 | CI configuration exists | PASS/FAIL | [details] |
| 3.2 | CI has security scanning | PASS/FAIL/N/A | [details] |
| 3.3 | Branch protection enabled | PASS/FAIL/N/A | [details] |

### 4. Security Documentation

| # | Check | Result | Details |
|---|-------|--------|---------|
| 4.1 | SECURITY.md exists | PASS/FAIL | [details] |
| 4.2 | Security reporting instructions | PASS/FAIL/N/A | [details] |

### 5. Code Security

| # | Check | Result | Details |
|---|-------|--------|---------|
| 5.1 | Security linting configured | PASS/FAIL/N/A | [details] |
| 5.2 | TypeScript strict mode | PASS/FAIL/N/A | [details] |
| 5.3 | CSP headers configured | PASS/FAIL/N/A | [details] |

### 6. Container Security

| # | Check | Result | Details |
|---|-------|--------|---------|
| 6.1 | Non-root user in Dockerfile | PASS/FAIL/N/A | [details] |
| 6.2 | Multi-stage build | PASS/FAIL/N/A | [details] |
| 6.3 | Specific base image tags | PASS/FAIL/N/A | [details] |

## Recommendations

[For each FAIL item, provide a specific fix command or action:]

### Fix: [Check Name]

[What to do, with exact commands or file changes needed]

---

[Repeat for each FAIL]

## Notes

- N/A checks are excluded from the score calculation
- This check evaluates security infrastructure, not code content — run `/security-audit` for AI code analysis or `/security-scan` for tool-based scanning
```

---

## Phase 5: Cleanup & Present

Present to the user:

1. **Grade**: Letter grade and percentage
2. **FAIL items**: List each failed check with a one-line fix suggestion
3. **Top recommendations**: 3 most impactful actions to improve the score
4. **Artifact path**: `docs/analysis/security-posture-${SCAN_ID}.md`
5. **Complement**: "For code-level security analysis, run `/security-audit`. For tool-based scanning (SAST, dependencies, secrets), run `/security-scan`."

---

## Rules

- **Read-only analysis** — do NOT modify any source code or configuration
- **Never use `cd`** — use absolute paths everywhere
- Use Read/Glob tools for file checks — not Bash (except for git/gh commands)
- Quote all bash variables: `"${VAR}"`
- **Minimize permission prompts** — combine related Bash commands (e.g., preflight checks) into single calls. Only keep separate commands where individual exit-code handling is needed.
- **Never use `$()` or pipe to `jq`** — run standalone, parse JSON natively
- Do NOT commit the report automatically — let the user decide
- N/A checks excluded from scoring — never penalize for inapplicable checks
- No state file needed — single-pass execution, no loops
