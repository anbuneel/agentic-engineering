# Skills Guide

Visual flow diagrams for every skill in the Agentic Engineering toolkit. For detailed descriptions and setup instructions, see the [README](../README.md).

## Quick Navigation

| Category | Skills | Pattern |
|----------|--------|---------|
| Collaboration | `/peer-review-code`, `/peer-review-plan`, `/peer-ideate` | Counter-review + convergence |
| Workflow | `/merge` | Linear pipeline |
| Security | `/security-scan`, `/security-audit`, `/security-posture` | Analysis + reporting |

---

## `/peer-review-code` — Multi-Agent Code Review

Multi-round review across Codex CLI and GitHub bots with counter-review, decision gates, and convergence tracking. Min 2 rounds, max 5.

```mermaid
graph TD
    A[Preflight] --> B{Diff < 20 lines?}
    B -- Yes --> D[Pre-Review]
    B -- No --> C["/simplify"]
    C --> D

    D --> D1[code-reviewer]
    D --> D2[silent-failure-hunter]
    D --> D3[type-design-analyzer]
    D1 & D2 & D3 --> E[Counter-Review + Decision Gate]
    E --> F[Fix + Quality Gates + Commit]
    F --> G[Create PR + Push]

    G --> H[Round N]

    subgraph "Review Loop (2-5 rounds)"
        H --> I[Task 1: Codex CLI Review]
        H --> J["Task 2: Poll GH Bots\n(8 min R1 / 4 min R2+)"]
        I & J --> K[Sync Point]
        K --> L["Consolidate + GH Bot Verification\n(fingerprint cross-check)"]
        L --> M[Counter-Review + Decision Gate]
        M --> N{Converged?}
        N -- "No (fixes needed)" --> O[Fix + Quality Gates + Commit]
        O --> P[Push]
        P --> H
    end

    N -- Yes --> Q[Finalize]
    Q --> R[Deferred Items → GH Issues]
    Q --> S[Update PR Description]
    Q --> T[Write Review Artifact]
```

> **Requires:** git, gh, Codex CLI. Optional: GitHub bot apps (Claude, Devin, Codex GH)
>
> **Output:** `docs/reviews/code-review-{id}.md`
>
> **Key features:** Parallel Codex + GH bot polling, GH bot finding verification via cross-round fingerprinting, MUST FIX committed before SHOULD FIX (safe rollback), adaptive polling timeout

---

## `/peer-review-plan` — Two-Agent Plan Review

Claude and Codex CLI take turns reviewing a plan document. Each round: Codex reviews, Claude counter-reviews with dispositions, user resolves disputes, Claude revises. Min 2 rounds, max 5.

```mermaid
graph TD
    A[Setup + Read Plan] --> B[Codex Review]
    B --> C{Verdict?}

    C -- "REVISE (or Round < 2)" --> D[Counter-Review]
    D --> E{Reject or Defer?}
    E -- Yes --> F[Decision Gate: User Breaks Tie]
    E -- No --> G[Revise Plan]
    F --> G
    G --> H["Resume Codex (same session)"]
    H --> C

    C -- "APPROVED (Round ≥ 2)" --> I[Write Review Artifact]
    C -- "Max Rounds (5)" --> I
```

> **Requires:** Codex CLI
>
> **Output:** `docs/reviews/plan-review-{id}.md`
>
> **Key features:** Codex session resume (context preserved across rounds), full audit trail of every finding + disposition + revision

---

## `/peer-ideate` — Multi-Model Brainstorming Council

Three models brainstorm independently on any topic, then Claude synthesizes and each model counter-reviews. Works with any subset of models.

```mermaid
graph TD
    A[Capture Brief] --> B[Parallel Brainstorming]

    B --> C[Claude]
    B --> D["Codex (optional)"]
    B --> E["Gemini (optional)"]

    C & D & E --> F[Claude Synthesizes]
    F --> G[Tag Consensus Levels]
    G --> H[Counter-Review]

    H --> I["Codex: endorse / challenge / enhance / new"]
    H --> J["Gemini: endorse / challenge / enhance / new"]
    H --> K["Claude: self-critique"]

    I & J & K --> L[Final Report]
    L --> M{User Choice}

    M -- Pick Ideas --> N[Act on Selected]
    M -- Go Deeper --> B
    M -- Export --> O[Save + Cleanup]
```

> **Requires:** Claude (always). Optional: Codex CLI, Gemini CLI
>
> **Output:** `{review-dir}/report-{id}.md`
>
> **Key features:** Same brief to all models (no cross-contamination), consensus/unique/contested tagging, supports file and image attachments

---

## `/merge` — Squash-Merge with Auto-Documentation

One-command workflow to squash-merge a PR and update all project docs in a single pass.

```mermaid
graph LR
    A[Preflight] --> B[Squash-Merge PR]
    B --> C[Switch to Target Branch]
    C --> D[Pull Latest]
    D --> E{Docs Need Updating?}
    E -- Yes --> F["Update README,\nCHANGELOG, CLAUDE.md"]
    F --> G[Commit + Push]
    E -- No --> H[Skip]
    G --> I[Delete Feature Branch]
    H --> I
```

> **Requires:** git, gh
>
> **Key features:** Safe delete only (`-d` not `-D`), only updates existing docs (never creates new files), reports merge failures instead of retrying

---

## `/security-scan` — SAST, Dependencies, and Secrets

Runs available scanning tools and generates a consolidated report. Auto-detects which tools are installed.

```mermaid
graph TD
    A[Preflight] --> B[Detect Tools]

    B --> C{Semgrep?}
    B --> D{npm audit?}
    B --> E{Gitleaks?}

    C -- Installed --> F[SAST Scan]
    C -- Missing --> F2[Skip + Warn]
    D -- "package.json exists" --> G[Dependency Audit]
    D -- "No package.json" --> G2[Skip]
    E -- Installed --> H[Secret Detection]
    E -- Missing --> H2[Skip + Warn]

    F & F2 & G & G2 & H & H2 --> I[Consolidated Report]
    I --> J["docs/analysis/security-scan-{id}.md"]
```

> **Requires:** git + at least one of: Semgrep, Gitleaks, or npm
>
> **Output:** `docs/analysis/security-scan-{id}.md`
>
> **Key features:** Read-only (no code changes), secret values never written to report, non-zero scanner exit codes handled correctly

---

## `/security-audit` — AI-Driven Security Review

Full-codebase security analysis using multiple AI agents with counter-review. Maps findings to OWASP Top 10.

```mermaid
graph TD
    A[Preflight + Detect Project Type] --> B[Parallel AI Analysis]

    B --> C[code-reviewer\nInjection, auth, data exposure]
    B --> D[silent-failure-hunter\nFail-open, swallowed exceptions]
    B --> E[type-design-analyzer\nType coercion, unsafe casts]
    B --> F[Claude Native\nOWASP Top 10 mapping]
    B --> G["Codex CLI (optional)\nComprehensive audit"]

    C & D & E & F & G --> H[Deduplicate Findings]
    H --> I[Counter-Review]
    I --> J{Reject or Defer?}
    J -- Yes --> K[Decision Gate: User Decides]
    J -- No --> L[Generate Report]
    K --> L

    L --> M["docs/analysis/security-audit-{id}.md"]
```

> **Requires:** git. Optional: Codex CLI
>
> **Output:** `docs/analysis/security-audit-{id}.md`
>
> **Key features:** Read-only, OWASP Top 10 coverage table, project-type-specific checks (web, node, python, docker), secrets always redacted

---

## `/security-posture` — Security Hygiene Scorecard

Fast infrastructure check across 16 items in 6 categories. Returns a letter grade (A-F) with specific fix recommendations. No scanning tools needed.

```mermaid
graph TD
    A[Preflight + Detect Project Type] --> B[Run 16 Checks]

    B --> C["1. Secret Management (3 checks)\nGitignore, history, pre-commit hooks"]
    B --> D["2. Dependency Management (2 checks)\nLock files, automated updates"]
    B --> E["3. CI/CD Security (3 checks)\nCI config, security scanning, branch protection"]
    B --> F["4. Security Docs (2 checks)\nSECURITY.md, reporting instructions"]
    B --> G["5. Code Security (3 checks)\nLinting, strict mode, CSP headers"]
    B --> H["6. Container Security (3 checks)\nNon-root, multi-stage, image tags"]

    C & D & E & F & G & H --> I["Score: PASS / (PASS + FAIL)"]
    I --> J["Grade: A-F"]
    J --> K["docs/analysis/security-posture-{id}.md"]
```

> **Requires:** git. Optional: gh (for branch protection check)
>
> **Output:** `docs/analysis/security-posture-{id}.md`
>
> **Key features:** Zero dependencies beyond git, N/A checks excluded from scoring, actionable fix commands for every FAIL item

---

## Shared Patterns

Four patterns that appear across multiple skills:

```mermaid
graph LR
    subgraph "Counter-Review"
        CR1[Agent Finding] --> CR2{Claude Evaluates}
        CR2 --> CR3[agree / partial / defer / reject]
    end

    subgraph "Decision Gate"
        DG1[reject or defer] --> DG2[Present Both Sides]
        DG2 --> DG3[User Breaks Tie]
    end

    subgraph "Convergence Loop"
        CL1[Review] --> CL2[Fix]
        CL2 --> CL3{All Resolved?\nMin 2 rounds}
        CL3 -- No --> CL1
        CL3 -- Yes --> CL4[Done]
    end

    subgraph "State Persistence"
        SP1[JSON State File] --> SP2[Survives Context\nCompaction]
        SP2 --> SP3[Variables Restored\nEach Round]
    end
```

| Pattern | Used By | Purpose |
|---------|---------|---------|
| Counter-review | `/peer-review-code`, `/peer-review-plan`, `/security-audit` | Claude critically evaluates findings instead of blindly accepting |
| Decision gate | `/peer-review-code`, `/peer-review-plan`, `/security-audit` | Human-in-the-loop only on disagreements |
| Convergence loop | `/peer-review-code`, `/peer-review-plan` | Can't exit until fixes are verified clean |
| State persistence | `/peer-review-code`, `/peer-review-plan`, `/security-audit` | JSON state file survives context window compaction |
