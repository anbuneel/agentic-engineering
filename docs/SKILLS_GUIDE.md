# Skills Guide

Visual flow diagrams for every shipped skill in the Agentic Engineering toolkit. For detailed descriptions and setup instructions, see the [README](../README.md).

## Quick Navigation

| Category | Skills | Pattern |
|----------|--------|---------|
| Collaboration | `/multi-agent-code-review`, `/multi-agent-plan-review`, `/multi-agent-ideate` | Primary driver + reviewer registry + counter-review |
| Workflow | `/merge` | Linear pipeline |
| Security | `/security-scan`, `/security-audit`, `/security-posture` | Analysis + reporting |

---

## Shared Runtime Model

Multi-agent skills use a runtime adapter and reviewer registry instead of assuming one primary agent. The primary driver is detected as `claude-code`, `codex-app`, `codex-cli`, or `unknown`. Reviewers are classified as primary-native, native subagents, external CLI reviewers, GitHub review agents, skipped, or secondary same-family.

External reviewers are advisory by default. A reviewer becomes required only when the user explicitly requests it; skipped advisory reviewers reduce confidence but do not block convergence. Reviewer channels are Claude and Codex. Each multi-agent skill carries `references/reviewer-contracts.md` (commands, flags, resume, failure handling, effort mapping) and, where findings are structured, `references/findings-schema.md` (one JSON object per reviewer per round, enforced with `--json-schema` on Claude and `--output-schema` on Codex). Three read-only lens agents ship with the plugin: `code-reviewer`, `silent-failure-hunter`, `type-design-analyzer`.

---

## `/multi-agent-code-review` — Multi-Agent Code Review

Review across the primary driver, three lens agents, the cross-family CLI reviewer, and GitHub review agents, with counter-review on every finding and convergence tracking. Round 1 fans out to everyone; verification rounds run only after fixes and only for the reviewers whose findings were acted on. A clean round 1 converges. Max 5 rounds. The loop never blocks on the user.

```mermaid
graph TD
    A["Preflight: clean tree, base branch,\nquality gates, schema, rebase once, PR"] --> B[Round 1: fan out]

    B --> B0[Primary-Native Review]
    B --> B1[code-reviewer lens]
    B --> B2[silent-failure-hunter lens]
    B --> B3[type-design-analyzer lens]
    B --> B4["Cross-family CLI reviewer\n(Codex under Claude, Claude under Codex)"]
    B --> B5["GH review agents\n(poll up to 8 min)"]
    B0 & B1 & B2 & B3 & B4 & B5 --> C["Consolidate on fingerprint\n+ GH finding verification"]
    C --> D[Counter-Review]
    D --> D1["reject / defer → Needs your call\n(recorded, not blocking)"]
    D --> E{Converged?}
    E -- "Fixes this round" --> F["Fix MUST_FIX, gates, commit\nFix SHOULD_FIX, gates, commit"]
    F --> G[Push + round summary comment]
    G --> H["Verification round:\nresume only reviewers whose\nfindings were acted on;\npoll bots only after a push"]
    H --> C

    E -- "No fixes, bots verified" --> I[Finalize]
    I --> J[Needs your call presented]
    I --> K[Deferred Items → GH Issues]
    I --> L[PR description + final comment]
    I --> M[Review artifact]
```

> **Requires:** git, gh. Optional: Claude or Codex CLI as the cross-family reviewer, GitHub bot apps (Claude, Devin, Codex GH)
>
> **Options:** `effort=<fast|balanced|deep>`, `model=<fable|opus|sonnet|haiku>`, `budget=<usd>`, `decisions=<deferred|interactive>` (default deferred), `require=<reviewer>`
>
> **Output:** `docs/reviews/code-review-{id}.md`
>
> **Key features:** Fan out once and verify narrowly, findings as one JSON object per reviewer, reject and defer recorded with both arguments instead of blocking, GH finding verification via cross-round fingerprinting, quality gates from the project's `CLAUDE.md`/`AGENTS.md` or detected from build files, MUST_FIX committed before SHOULD_FIX (safe rollback)

---

## `/multi-agent-plan-review` — Two-Agent Plan Review

The primary driver sends a plan document to the cross-family reviewer. Each round: the reviewer returns a findings object, the primary driver counter-reviews with dispositions, agreed items revise the plan, and the reviewer session is resumed to verify. Reject and defer are recorded under Needs your call; the loop never waits. A round with nothing to revise converges. Max 5 rounds.

```mermaid
graph TD
    A[Setup + Read Plan + Schema] --> B[Reviewer Pass: findings object]
    B --> C[Counter-Review]
    C --> C1["reject / defer → Needs your call\n(recorded, not blocking)"]
    C --> D{Revisions this round?}
    D -- Yes --> E[Revise Plan]
    E --> F[Resume Reviewer Session]
    F --> B
    D -- "No (or max rounds)" --> G[Write Review Artifact]
```

> **Requires:** primary driver. Optional: Claude or Codex CLI as the cross-family reviewer
>
> **Options:** `effort=<fast|balanced|deep>`, `model=<fable|opus|sonnet|haiku>`, `budget=<usd>`, `decisions=<deferred|interactive>` (default deferred), `require=<reviewer>`
>
> **Output:** `docs/reviews/plan-review-{id}.md`
>
> **Key features:** reviewer session resume, findings as one JSON object per round, Needs your call instead of a blocking gate, full audit trail of every finding + disposition + revision

---

## `/multi-agent-ideate` — Multi-Model Brainstorming Council

Available participants brainstorm independently on any topic, then the primary driver synthesizes and each participant counter-reviews. Works with any subset of models.

```mermaid
graph TD
    A[Capture Brief] --> B[Parallel Brainstorming]

    B --> C[Primary Driver]
    B --> D["Claude Reviewer (optional)"]
    B --> E["Codex Reviewer (optional)"]

    C & D & E --> G[Primary Driver Synthesizes]
    G --> H[Counter-Review]

    H --> I["External Participants:\nendorse / challenge / enhance / new"]
    H --> K["Primary Driver:\nself-critique"]

    I & K --> L[Final Report]
    L --> M{User Choice}

    M -- Pick Ideas --> N[Act on Selected]
    M -- Go Deeper --> B
    M -- Export --> O[Save Report]
```

> **Requires:** primary driver. Optional: Claude/Codex reviewer channels
>
> **Options:** `effort=<fast|balanced|deep>`, `model=<fable|opus|sonnet|haiku>`, `budget=<usd>`
>
> **Output:** `{review-dir}/report-{id}.md`
>
> **Key features:** Same brief to all models (no cross-contamination), consensus/unique/contested tagging, supports file and image attachments

---

## `/merge` — Squash-Merge with Auto-Documentation

One-command workflow to squash-merge a PR and update all project docs in a single pass. Resumable: re-running after a successful merge picks up at the documentation step.

```mermaid
graph TD
    A["Preflight: probe capabilities,\nresolve PR (arg or branch)"] --> A2{"Target branch\nin sync?"}
    A2 -- "Ahead: PR would absorb\nunpushed commits" --> AZ[Stop before merging]
    A2 -- Yes --> B{PR state?}
    B -- MERGED --> C[Switch to Target Branch]
    B -- OPEN --> M[Squash-Merge]
    M --> N{GitHub reports merged?}
    N -- "Queued / auto-merge" --> Z[Stop: resume when merged]
    N -- Yes --> D[Delete remote branch]
    D --> C
    C --> E{Docs Need Updating?}
    E -- Yes --> F["Update README,\nCHANGELOG, CLAUDE.md"]
    F --> G{Push accepted?}
    G -- Protected --> H[Follow-up docs PR]
    G -- Yes --> I{Branch present + free?}
    E -- No --> I
    H --> I
    I -- "Absent / protected / unverifiable" --> K[Keep + record reason]
    I -- Yes --> J["patch-id --verbatim:\nbranch diff vs squash diff"]
    J -- Equal --> L["Re-check tip, delete with -D"]
    J -- Differ --> K
    L --> O[Repo-Wide Branch Sweep]
    K --> O
    O --> P["Report: completed,\noutstanding, branch inventory"]
```

> **Requires:** git + (gh or GitHub MCP)
>
> **Key features:** Stops before merging when the local target branch is ahead of its remote, because a PR branched from a stale target silently absorbs its unpushed commits into the squash, content-proof branch deletion (`git patch-id --verbatim`, since a squash merge breaks the ancestry that `-d` tests and the default algorithm ignores whitespace), confirms GitHub actually merged rather than queued, repo-wide sweep across local branches, remote branches and stale tracking refs, never deletes a protected or worktree-held branch or one it could not verify, falls back to a follow-up PR when the target rejects direct pushes, reports outstanding work alongside a full branch inventory

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

Full-codebase security analysis using primary-native analysis, available native subagents, and external reviewer channels with counter-review. Maps findings to OWASP Top 10.

```mermaid
graph TD
    A[Preflight + Detect Project Type] --> B[Parallel AI Analysis]

    B --> C[code-reviewer lens\nInjection, auth, data exposure]
    B --> D[silent-failure-hunter lens\nFail-open, swallowed exceptions]
    B --> E[type-design-analyzer lens\nType coercion, unsafe casts]
    B --> F[Primary-Native\nOWASP Top 10 mapping]
    B --> G["External Reviewers\nClaude / Codex"]

    C & D & E & F & G --> H[Deduplicate Findings]
    H --> I[Counter-Review]
    I --> J{Reject or Defer?}
    J -- Yes --> K[Decision Gate: User Decides]
    J -- No --> L[Generate Report]
    K --> L

    L --> M["docs/analysis/security-audit-{id}.md"]
```

> **Requires:** git. Optional: Claude/Codex reviewer channels
>
> **Options:** `effort=<fast|balanced|deep>`, `model=<fable|opus|sonnet|haiku>`, `budget=<usd>`
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
        CR1[Agent Finding] --> CR2{Primary Driver Evaluates}
        CR2 --> CR3[agree / partial / defer / reject]
    end

    subgraph "Needs Your Call"
        DG1[reject or defer] --> DG2[Record Both Sides]
        DG2 --> DG3[Presented at the End]
    end

    subgraph "Convergence Loop"
        CL1[Review] --> CL2[Fix]
        CL2 --> CL3{Fixes this round?}
        CL3 -- Yes --> CL5[Verify with the reviewers involved]
        CL5 --> CL3
        CL3 -- No --> CL4[Done]
    end

    subgraph "State Persistence"
        SP1[JSON State File] --> SP2[Survives Context\nCompaction]
        SP2 --> SP3[Variables Restored\nEach Round]
    end
```

| Pattern | Used By | Purpose |
|---------|---------|---------|
| Counter-review | `/multi-agent-code-review`, `/multi-agent-plan-review`, `/security-audit` | Primary driver critically evaluates findings instead of blindly accepting |
| Needs your call | `/multi-agent-code-review`, `/multi-agent-plan-review` (`/security-audit` keeps its pre-report decision gate) | Disagreements recorded with both arguments and surfaced at the end; the loop never waits |
| Convergence loop | `/multi-agent-code-review`, `/multi-agent-plan-review` | Every round that fixes something is followed by a verification round |
| State persistence | `/multi-agent-code-review`, `/multi-agent-plan-review`, `/security-audit` | JSON state file survives context window compaction |
